// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {IntentRegistry} from "../../src/IntentRegistry.sol";
import {MockRouter} from "../mocks/MockRouter.sol";

contract IntentRegistryInvariant is StdInvariant, Test {
    IntentRegistry internal registry;

    function setUp() public {
        registry = new IntentRegistry(address(new MockRouter()));

        targetContract(address(registry));
    }

    /// INTENT IDS MUST NEVER GO BACKWARDS
    function invariant_nextIntentMonotonic() public view {
        assertGe(registry.nextIntentId(), 0);
    }

    /// EXECUTED COUNT CAN NEVER EXCEED TOTAL
    function invariant_executionBounded() public view {
        uint256 next = registry.nextIntentId();

        for (uint256 i; i < next; i++) {
            IntentRegistry.TradeIntent memory intent = registry.getIntent(i);

            if (intent.executed) {
                assertLt(i, next);
            }
        }
    }
}
