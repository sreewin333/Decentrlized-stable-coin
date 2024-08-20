// SPDX-License-Identifier:MIT
pragma solidity 0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    DeployDSC deployer;
    HelperConfig config;
    address wethAddress;
    address btcAddress;
    address wethPriceFeedAddress;
    address wbtcPriceFeedAddress;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

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

    ///////////////////////////
    //deposit collateral test//
    //////////////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(wethAddress, 0);
        vm.stopPrank();
    }
}
