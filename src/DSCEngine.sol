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

    function depositCollateralAndMintDsc() external {}

    function depositCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        external
        moreThanZero(collateralAmount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += collateralAmount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, collateralAmount);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}
    function redeemCollateral() external {}
    /**
     *
     * @param amountDscToMint the amount of Decentralized stable coin to mint
     * @notice they must have more collateral value greater than the minimum threshold
     */

    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc() external {}
    function liquidate() external {}
    function getHealthFactor() external view {}

    ////////////////////////////////////////
    // private and internal view Functions//
    ///////////////////////////////////////

    /**
     * Returns how close to liquidation a user is
     * if a user goes below 1,they can get liquidated.
     *
     */
    function _healthFactor(address user) private view returns (uint256) {
        //1.we need total dsc minted for the user
        //2. the total value of the collateral for the user
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        //1. check health factor (do they have enough collateral?
        //2.revert if they dont
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
