// SPDX-License-Identifier:MIT
pragma solidity 0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.4/interfaces/AggregatorV3Interface.sol";
/**
 * @title OracleLib
 * @author Sreewin M B
 * @notice this is a library to check the chainlink oracle for stale data.
 * If the chainlink price feed is stale, the function will revert and render DSCEngine Unusable.
 */

library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface pricefeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            pricefeed.latestRoundData();

        uint256 secondSince = block.timestamp - updatedAt;
        if (secondSince > TIMEOUT) revert OracleLib__StalePrice();

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
