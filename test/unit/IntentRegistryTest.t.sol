// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IntentRegistry} from "../../src/IntentRegistry.sol";
import {MockRouter} from "../mocks/MockRouter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract IntentRegistryTest is Test {
    IntentRegistry internal registry;
    MockRouter internal router;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;

    address internal user = address(1);

    bytes32 internal secret = keccak256("secret");

    function setUp() public {
        router = new MockRouter();
        registry = new IntentRegistry(address(router));

        tokenA = new MockERC20("A", "A");
        tokenB = new MockERC20("B", "B");

        tokenA.mint(user, 1e24);
    }

    function _hash(uint256 expiry) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                user, address(tokenA), address(tokenB), uint256(100 ether), uint256(1000), true, expiry, secret
            )
        );
    }

    /// INTENT MUST SUBMIT CLEANLY
    function testSubmitIntent() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(user);
        registry.submitIntent(_hash(expiry), expiry);

        assertEq(registry.nextIntentId(), 1);
    }

    /// EXPIRED INTENT MUST DIE IMMEDIATELY
    function testRevertIfExpiryPassed() public {
        vm.prank(user);

        vm.expectRevert(IntentRegistry.IntentRegistry__ExpiryPassed.selector);

        registry.submitIntent(bytes32(0), block.timestamp);
    }

    /// ONLY OWNER CAN REVEAL
    function testOnlyOwnerReveal() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(user);
        registry.submitIntent(_hash(expiry), expiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__NotIntentOwner.selector);

        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, true, secret);
    }

    /// HASH MISMATCH MUST REVERT
    function testRevealHashMismatch() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(user);
        registry.submitIntent(_hash(expiry), expiry);

        vm.prank(user);

        vm.expectRevert(IntentRegistry.IntentRegistry__RevealHashMismatch.selector);

        registry.revealIntent(0, address(tokenA), address(tokenB), 999, 1000, true, secret);
    }

    /// EXECUTION MUST COMPLETE WHEN CONDITION IS TRUE
    function testExecuteIntent() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.startPrank(user);

        registry.submitIntent(_hash(expiry), expiry);

        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, true, secret);

        tokenA.approve(address(registry), 100 ether);

        registry.depositIntentFunds(0);

        vm.stopPrank();

        registry.executeIntent(0, 1001);

        IntentRegistry.TradeIntent memory intent = registry.getIntent(0);

        assertTrue(intent.executed);
    }

    /// PRICE FAILURE MUST BLOCK EXECUTION
    function testExecutionConditionFails() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.startPrank(user);

        registry.submitIntent(_hash(expiry), expiry);

        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, true, secret);

        tokenA.approve(address(registry), 100 ether);
        registry.depositIntentFunds(0);

        vm.stopPrank();

        vm.expectRevert(IntentRegistry.IntentRegistry__PriceConditionNotMet.selector);

        registry.executeIntent(0, 999);
    }
}
