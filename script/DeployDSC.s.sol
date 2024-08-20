// SPDX-License-Identifier:MIT
pragma solidity 0.8.18;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";

contract DeployDSC is Script {
    address[] public PriceFeedAddresses;
    address[] public tokenAddresses;

    function run() public returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (
            address WethAddress,
            address BtcAddress,
            address WethPriceFeedAddress,
            address WbtcPriceFeedAddress,
            uint256 deployerKey
        ) = config.ActiveNetworkConfig();
        tokenAddresses = [WethAddress, BtcAddress];
        PriceFeedAddresses = [WethPriceFeedAddress, WbtcPriceFeedAddress];

        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, PriceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (dsc, engine, config);
    }
}
