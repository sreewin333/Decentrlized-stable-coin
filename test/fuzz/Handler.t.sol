// SPDX-License-Identifier:MIT
pragma solidity 0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public ghostvariable;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dsce = _dscEngine;
        dsc = _dsc;
        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralseed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralSeed(collateralseed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        vm.stopPrank();
        dsce.depositCollateral(address(collateral), amountCollateral);
    }

    function mintDsc(uint256 amountToMint) public {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(msg.sender);
        uint256 maxDscToMint = (collateralValueInUsd / 2) - totalDscMinted;
        amountToMint = bound(amountToMint, 0, maxDscToMint);

        if (amountToMint == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        dsce.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralseed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralSeed(collateralseed);
        uint256 maxCollateralToRoedeem = dsce.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRoedeem);
        if (amountCollateral == 0) {
            return;
        }
        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    function _getCollateralSeed(uint256 collateralseed) private view returns (ERC20Mock) {
        if (collateralseed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
