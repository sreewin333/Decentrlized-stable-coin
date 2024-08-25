// SPDX-License-Identifier:MIT
pragma solidity 0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../Mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    event CollateralDeposited(
        address indexed user, address indexed collateralAddress, uint256 indexed CollateralAmount
    );

    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    DeployDSC deployer;
    HelperConfig config;
    address wethAddress;
    address btcAddress;
    address wethPriceFeedAddress;
    address wbtcPriceFeedAddress;
    address public USER = makeAddr("user");
    address public liquidator = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 20 ether;
    uint256 amountToMint = 100 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (address WethAddress, address BtcAddress, address WethPriceFeedAddress, address WbtcPriceFeedAddress,) =
            config.ActiveNetworkConfig();
        wethAddress = WethAddress;
        btcAddress = BtcAddress;
        wethPriceFeedAddress = WethPriceFeedAddress;
        wbtcPriceFeedAddress = WbtcPriceFeedAddress;
        vm.deal(USER, 10 ether);
        ERC20Mock(wethAddress).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(btcAddress).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wethAddress).mint(liquidator, 2e22);
    }
    ////////////////////
    //Constructor tests//
    /////////////////////

    address[] public PricefeedAddresses;
    address[] public TokenAddresses;

    function testConstructoAddressesShouldMatch() public {
        PricefeedAddresses = [wethPriceFeedAddress, wbtcPriceFeedAddress];
        TokenAddresses = [wethAddress];
        vm.expectRevert(DSCEngine.DSCEngine__tokenAddressAndPriceFeedAddressMustBeSameLength.selector);
        new DSCEngine(TokenAddresses, PricefeedAddresses, address(dscEngine));
    }

    ///////////////
    //price tests//
    ///////////////

    function testGetUsdValue() public view {
        uint256 amount = 15;
        //2000 * 15 * 1e18 =30,000e18;
        uint256 actualvalue = dscEngine.getUsdValue(wethAddress, amount);
        uint256 expectedvalue = 30000;
        assertEq(actualvalue, expectedvalue);
    }

    function testgetTokenAmountFromUsd() public view {
        uint256 USDAmount = 1000 ether;
        uint256 expectedamount = 0.5 ether;
        uint256 actualAmount = dscEngine.getTokenAmountFromUsd(wethAddress, USDAmount);
        assertEq(actualAmount, expectedamount);
    }

    ///////////////////////////
    //deposit collateral test//
    //////////////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(wethAddress, 0 ether);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("Fake", "Fake", USER, 10 ether);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(ranToken), 1 ether);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDSCMinted, uint256 CollateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedtotalDscMinted = 0;
        uint256 expectedDepositedAmount = dscEngine.getTokenAmountFromUsd(wethAddress, CollateralValueInUsd);
        assertEq(totalDSCMinted, expectedtotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositedAmount);
    }

    function testDepositCollateralEmitEvent() public {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false, address(dscEngine));
        emit CollateralDeposited(USER, wethAddress, AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(wethAddress, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCandepositcollateral() public {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(wethAddress, AMOUNT_COLLATERAL);
    }

    /////////////////
    //mint Dsc test//
    ////////////////
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(wethAddress, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testIfMintAmountIsZero() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDsc(0);
    }

    function testMintDscRevertIfHealthFactorIsBroken() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorBroken.selector);
        dscEngine.mintDsc(1e22 + 1);
        vm.stopPrank();
    }

    function testMintDsc() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.mintDsc(10);
        uint256 expectedAmountDsc = 10;
        uint256 actualAmountDsc = dscEngine.getDscMintedForUser();
        assertEq(expectedAmountDsc, actualAmountDsc);
        vm.stopPrank();
    }
    ////////////////////////
    // Health Factor Tests//
    ////////////////////////

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(wethAddress, AMOUNT_COLLATERAL);
        dscEngine.mintDsc(10);
        vm.stopPrank();
        _;
    }

    function testUsersHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 UserHealthFactor = dscEngine.getHealthFactorOfuser(USER);
        assert(UserHealthFactor > 1);
        console.log(UserHealthFactor);
    }
    ////////////////////////
    // Collateral Tests  //
    ///////////////////////

    function testUserAllCollateralValue() public depositedCollateral {
        vm.startPrank(USER);
        ERC20Mock(btcAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(btcAddress, AMOUNT_COLLATERAL);
        uint256 expectedCollateralValue = 3e22;
        uint256 actualcollateralValue = dscEngine.getAccountCollateralValue(USER);
        vm.stopPrank();
        assert(expectedCollateralValue == actualcollateralValue);
    }
    //////////////////
    // BurnDSC tests//
    //////////////////

    function testCantBurnMoreThanTheUserhas() public {
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.burnDsc(1);
    }

    function testRevertIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(wethAddress, AMOUNT_COLLATERAL, amountToMint);
        uint256 UserBalance = dsc.balanceOf(USER);
        console.log(UserBalance);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDsc(0);
        vm.stopPrank();
    }

    function testUserCanBurnDsc() public {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(wethAddress, AMOUNT_COLLATERAL, amountToMint);
        dsc.approve(address(dscEngine), amountToMint);
        dscEngine.burnDsc(amountToMint);
        vm.stopPrank();
    }
    ////////////////////////////
    ///RedeemCollateral tests///
    ////////////////////////////

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.redeemCollateral(wethAddress, 5 ether);
    }

    function testRedeemcollateralForDSCWorks() public {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(wethAddress, AMOUNT_COLLATERAL, 100 ether); //100 ether
        dsc.approve(address(dscEngine), 100 ether);
        dscEngine.redeemCollateralForDsc(wethAddress, AMOUNT_COLLATERAL, 100 ether);
        vm.stopPrank();
    }
    ////////////////////////////
    /// liquidation  tests  ////
    ////////////////////////////

    function testliquidationChecksOkHealthFactor() public depositedCollateralAndMintedDsc {
        vm.startPrank(liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(wethAddress, USER, 10 ether);
    }

    function testDebtoCoverWorksCorrectly() public {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(wethAddress, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        int256 ethUsdUpdatedPrice = 18e8;
        MockV3Aggregator(wethPriceFeedAddress).updateAnswer(ethUsdUpdatedPrice);
        uint256 UsersHealthFactor = dscEngine.getHealthFactorOfuser(USER);
        console.log(UsersHealthFactor);

        vm.startPrank(liquidator);
        ERC20Mock(wethAddress).approve(address(dscEngine), 20 ether);
        dscEngine.depositCollateralAndMintDsc(wethAddress, 20 ether, amountToMint);
        dsc.approve(address(dscEngine), amountToMint);
        dscEngine.liquidate(wethAddress, USER, amountToMint);
        vm.stopPrank();
    }

    function testfakeDebtoCoverWorksCorrectly() public {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(wethAddress, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        int256 ethUsdUpdatedPrice = 18e8;
        MockV3Aggregator(wethPriceFeedAddress).updateAnswer(ethUsdUpdatedPrice);
        uint256 UsersHealthFactor = dscEngine.getHealthFactorOfuser(USER);
        console.log(UsersHealthFactor);

        vm.startPrank(liquidator);
        ERC20Mock(wethAddress).approve(address(dscEngine), 20 ether);
        dscEngine.depositCollateralAndMintDsc(wethAddress, 20 ether, amountToMint);
        dsc.approve(address(dscEngine), amountToMint);
        dscEngine.liquidate(wethAddress, USER, amountToMint);
        vm.stopPrank();
    }
}
