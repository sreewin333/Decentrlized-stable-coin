// SPDX-License-Identifier:MIT
pragma solidity 0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/Mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct NetworkConfig {
        address WethAddress;
        address BtcAddress;
        address WethPriceFeedAddress;
        address WbtcPriceFeedAddress;
        uint256 deployerKey;
    }

    NetworkConfig public ActiveNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            ActiveNetworkConfig = GetSepoliaEthConfig();
        } else {
            ActiveNetworkConfig = GetOrCreateAnvilConfig();
        }
    }

    function GetSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            WethAddress: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            BtcAddress: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            WethPriceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            WbtcPriceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function GetOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (ActiveNetworkConfig.WethPriceFeedAddress != address(0)) {
            return ActiveNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator WethPricefeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock mockWeth = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);
        MockV3Aggregator WbtcPricefeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock mockBtc = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);
        vm.stopBroadcast();
        return (
            NetworkConfig({
                WethAddress: address(mockWeth),
                BtcAddress: address(mockBtc),
                WethPriceFeedAddress: address(WethPricefeed),
                WbtcPriceFeedAddress: address(WbtcPricefeed),
                deployerKey: DEFAULT_ANVIL_KEY
            })
        );
    }
}
