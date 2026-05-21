// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IntentRegistry} from "../../src/IntentRegistry.sol";
import {MockRouter} from "../mocks/MockRouter.sol";

contract IntentRegistryFuzz is Test {
    IntentRegistry internal registry;

    function setUp() public {
        registry = new IntentRegistry(address(new MockRouter()));
    }

    /// ANY FUTURE EXPIRY MUST SUBMIT
    function testFuzzSubmit(uint256 expiry) public {
        vm.assume(expiry > block.timestamp);

        registry.submitIntent(keccak256("x"), expiry);

        assertEq(registry.nextIntentId(), 1);
    }

    /// ANY PAST EXPIRY MUST REVERT
    function testFuzzRejectExpired(uint256 expiry) public {
        vm.assume(expiry <= block.timestamp);

        vm.expectRevert(IntentRegistry.IntentRegistry__ExpiryPassed.selector);

        registry.submitIntent(keccak256("x"), expiry);
    }
}
