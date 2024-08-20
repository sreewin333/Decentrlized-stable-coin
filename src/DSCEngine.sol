// SPDX-License-Identifier:MIT
pragma solidity 0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.4/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
/**
 * @title DSCEngine
 * @author Sreewin M B
 * @notice The system is designed to have the tokens maintain a value 1 token == $1 peg.
 * This stable coin has the properties :
 * Exogenous Collateral
 * Dollar pegged
 * Algorithmically stable
 *
 * it is similar to DAI if DAI had no governance,no fees,and was only backed by WBTC and WETH.
 *
 * Our Dsc system should always be "overCollateralized".At no point, should the value of all collateral <= the $ backed value of all the DSC.
 */

contract DSCEngine is ReentrancyGuard {
    ///////////
    //Errors///
    ///////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__tokenAddressAndPriceFeedAddressMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBroken();
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    //////////////////////
    // State Variables //
    ////////////////////

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable s_dsc;

    ///////////
    //Errors///
    ///////////
    event CollateralDeposited(
        address indexed user, address indexed collateralAddress, uint256 indexed CollateralAmount
    );
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed tokencollateralAddress,
        uint256 DscAmount
    );

    //////////////
    //Modifiers///
    /////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__tokenAddressAndPriceFeedAddressMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        s_dsc = DecentralizedStableCoin(dscAddress);
    }
    //////////////////////
    //External Functions//
    //////////////////////

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param collateralAmount The amount of collateral to be deposited.
     * @param amountToMint The amount of DSC to be minted.
     */
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 collateralAmount, uint256 amountToMint)
        external
    {
        depositCollateral(tokenCollateralAddress, collateralAmount);
        mintDsc(amountToMint);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += collateralAmount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, collateralAmount);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateralToRedeem)
        public
        moreThanZero(amountCollateralToRedeem)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateralToRedeem, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    /**
     *
     * @param tokenCollateralAddress The address of the collateral token to be redeemed.
     * @param amountCollateralToRedeem The amount of collateral to be redeemed.
     * @param amountToBurn The amount of DSC to be burned.
     * This function burns DSC and redeems the inderlying collateral in one transaction.
     */

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateralToRedeem,
        uint256 amountToBurn
    ) external {
        burnDsc(amountToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateralToRedeem);
        //revert not needed because, redeemCollateral checks is health factor is broken.
    }
    /**
     *
     * @param amountDscToMint the amount of Decentralized stable coin to mint
     * @notice they must have more collateral value greater than the minimum threshold
     */

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = s_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(uint256 burnAmount) public moreThanZero(burnAmount) {
        _burnDsc(burnAmount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    /**
     * F
     * @param CollateralToken ERC20 collateral address to liquidate from the user.
     * @param user The user who has broken the health factor(below 1).
     * @param debtToCover the amount of DSC to be burned to improve the users health factor.
     * @notice you can partially liquidate a user as long as they have a positive health factor.
     * @notice you will get a liquidation bonus for liquidating other people.
     *
     * This function assumes that the protocol is roughly 200% overcollateralized in order
     * for this to work
     */

    function liquidate(address CollateralToken, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        //1.checks the health factor of the user.
        uint256 StartingUserhealthfactor = _healthFactor(user);
        if (StartingUserhealthfactor >= 1e18) {
            revert DSCEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(CollateralToken, debtToCover);
        //additionally we are giving 10% bonus to the liquidator.
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * 10) / 100;
        uint256 totalCollaterlToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        // from user to the person who is liquidating the user ie(msg.sender);
        _redeemCollateral(CollateralToken, totalCollaterlToRedeem, user, msg.sender);
        //burn the DSC from the user.
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= StartingUserhealthfactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    ////////////////////////////////////////
    // private and internal view Functions//
    ///////////////////////////////////////
    function _burnDsc(uint256 amountOfDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DscMinted[onBehalfOf] -= amountOfDscToBurn;
        //address(this)
        bool success = s_dsc.transferFrom(dscFrom, address(s_dsc), amountOfDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        s_dsc.burn(amountOfDscToBurn);
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateralToRedeem,
        address from,
        address to
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateralToRedeem;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateralToRedeem);
        bool succes = IERC20(tokenCollateralAddress).transfer(to, amountCollateralToRedeem);
        if (!succes) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * Returns how close to liquidation a user is
     * if a user goes below 1,they can get liquidated.
     *
     */
    function _healthFactor(address user) private view returns (uint256) {
        //1.we need total dsc minted for the user
        //2. the total value of the collateral for the user
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * 50) / 100;
        return (collateralAdjustedForThreshold * 1e18) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        //1. check health factor (do they have enough collateral?
        //2.revert if they dont
        uint256 userhealthFactor = _healthFactor(user);
        if (userhealthFactor < 1e18) {
            revert DSCEngine__HealthFactorBroken();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }
    ///////////////////////////////////////////////
    //public and external view and pure Functions//
    //////////////////////////////////////////////

    function getTokenAmountFromUsd(address collateralToken, uint256 UsdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface pricefeed = AggregatorV3Interface(s_priceFeeds[collateralToken]);
        (, int256 price,,,) = pricefeed.latestRoundData();
        uint256 DebtCoveredValueInUsd = (UsdAmountInWei * 1e18) / (uint256(price) * 1e10);
        return DebtCoveredValueInUsd;
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        //loop through each collateral token,get the amount they have deposited,and map it to the price to get the USD value.
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface pricefeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = pricefeed.latestRoundData();
        //int256 returns  with 8 decimal places (ie, if 1000, int256 price = 1000 * 1e8);
        //that is why we are multiplying price ie,of 8 decibals with 1e10 to get,
        //18 decimals to match with the eth value and then divide them with 1e18 -
        //to get the price in USD
        return ((uint256(price) * 1e10) * amount) / 1e18;
    }
}
