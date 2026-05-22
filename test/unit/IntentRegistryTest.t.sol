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

    /// REVEALING TWICE MUST FAIL HARD
    function testRevealTwiceReverts() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.startPrank(user);

        registry.submitIntent(_hash(expiry), expiry);

        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, true, secret);

        vm.expectRevert(IntentRegistry.IntentRegistry__AlreadyRevealed.selector);

        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, true, secret);

        vm.stopPrank();
    }

    /// EXECUTION BEFORE REVEAL IS ILLEGAL
    function testExecuteWithoutRevealReverts() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(user);
        registry.submitIntent(_hash(expiry), expiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__IntentNotRevealed.selector);

        registry.executeIntent(0, 2000);
    }

    /// EXPIRED INTENTS MUST NEVER EXECUTE
    function testExpiredIntentReverts() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.startPrank(user);

        registry.submitIntent(_hash(expiry), expiry);

        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, true, secret);

        tokenA.approve(address(registry), 100 ether);
        registry.depositIntentFunds(0);

        vm.stopPrank();

        vm.warp(expiry + 1);

        vm.expectRevert(IntentRegistry.IntentRegistry__IntentExpired.selector);

        registry.executeIntent(0, 2000);
    }

    /// DOUBLE EXECUTION MUST FAIL
    function testExecuteTwiceReverts() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.startPrank(user);

        registry.submitIntent(_hash(expiry), expiry);

        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, true, secret);

        tokenA.approve(address(registry), 100 ether);
        registry.depositIntentFunds(0);

        vm.stopPrank();

        registry.executeIntent(0, 1001);

        vm.expectRevert(IntentRegistry.IntentRegistry__AlreadyExecuted.selector);

        registry.executeIntent(0, 1001);
    }

    /// LOWER-THAN STRATEGY MUST EXECUTE
    function testExecuteWhenPriceBelowTarget() public {
        uint256 expiry = block.timestamp + 1 days;

        bytes32 h = keccak256(
            abi.encodePacked(
                user, address(tokenA), address(tokenB), uint256(100 ether), uint256(1000), false, expiry, secret
            )
        );

        vm.startPrank(user);

        registry.submitIntent(h, expiry);

        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, false, secret);

        tokenA.approve(address(registry), 100 ether);
        registry.depositIntentFunds(0);

        vm.stopPrank();

        registry.executeIntent(0, 999);

        IntentRegistry.TradeIntent memory intent = registry.getIntent(0);

        assertTrue(intent.executed);
    }

    /// ONLY OWNER MAY DEPOSIT
    function testDepositByNonOwnerReverts() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(user);
        registry.submitIntent(_hash(expiry), expiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__NotIntentOwner.selector);

        registry.depositIntentFunds(0);
    }

    /// FAILED TOKEN TRANSFER MUST REVERT
    function testDepositTransferFail() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.startPrank(user);

        registry.submitIntent(_hash(expiry), expiry);

        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, true, secret);

        tokenA.setFail(true);

        vm.expectRevert(IntentRegistry.IntentRegistry__TransferFailed.selector);

        registry.depositIntentFunds(0);

        vm.stopPrank();
    }

    // --------------------------
    // State Integrity
    // --------------------------

    /// SUBMITTED INTENT FIELDS MUST BE STORED CORRECTLY
    function testSubmitIntentStoredCorrectly() public {
        uint256 expiry = block.timestamp + 1 days;
        bytes32 h = _hash(expiry);

        vm.prank(user);
        registry.submitIntent(h, expiry);

        IntentRegistry.TradeIntent memory intent = registry.getIntent(0);

        assertEq(intent.user, user);
        assertEq(intent.commitmentHash, h);
        assertEq(intent.expiry, expiry);
        assertEq(intent.tokenIn, address(0));
        assertEq(intent.tokenOut, address(0));
        assertEq(intent.amountIn, 0);
        assertFalse(intent.revealed);
        assertFalse(intent.executed);
    }

    /// REVEALED INTENT FIELDS MUST MATCH WHAT WAS PROVIDED
    function testRevealIntentPopulatesFields() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.startPrank(user);
        registry.submitIntent(_hash(expiry), expiry);
        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, true, secret);
        vm.stopPrank();

        IntentRegistry.TradeIntent memory intent = registry.getIntent(0);

        assertEq(intent.tokenIn, address(tokenA));
        assertEq(intent.tokenOut, address(tokenB));
        assertEq(intent.amountIn, 100 ether);
        assertEq(intent.targetPrice, 1000);
        assertTrue(intent.greaterThan);
        assertTrue(intent.revealed);
        assertFalse(intent.executed);
    }

    // --------------------------
    // nextIntentId
    // --------------------------

    /// NEXT INTENT ID MUST INCREMENT PER SUBMISSION
    function testNextIntentIdIncrementsOnMultipleSubmits() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.startPrank(user);
        registry.submitIntent(_hash(expiry), expiry);
        registry.submitIntent(_hash(expiry), expiry);
        registry.submitIntent(_hash(expiry), expiry);
        vm.stopPrank();

        assertEq(registry.nextIntentId(), 3);
    }

    /// EACH SUBMISSION MUST BELONG TO CORRECT SLOT
    function testMultipleIntentsAreIndependent() public {
        uint256 expiry = block.timestamp + 1 days;
        address user2 = address(2);

        vm.prank(user);
        registry.submitIntent(_hash(expiry), expiry);

        vm.prank(user2);
        registry.submitIntent(bytes32("other"), expiry + 1 hours);

        assertEq(registry.getIntent(0).user, user);
        assertEq(registry.getIntent(1).user, user2);
    }

    // --------------------------
    // Price Boundary Conditions
    // --------------------------

    /// PRICE EXACTLY AT TARGET WITH GREATER-THAN MUST EXECUTE (>=)
    function testExecuteAtExactTargetPriceGreaterThan() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.startPrank(user);
        registry.submitIntent(_hash(expiry), expiry);
        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, true, secret);
        tokenA.approve(address(registry), 100 ether);
        registry.depositIntentFunds(0);
        vm.stopPrank();

        registry.executeIntent(0, 1000); // price == targetPrice, greaterThan=true → should pass

        assertTrue(registry.getIntent(0).executed);
    }

    /// PRICE EXACTLY AT TARGET WITH LESS-THAN MUST EXECUTE (<=)
    function testExecuteAtExactTargetPriceLessThan() public {
        uint256 expiry = block.timestamp + 1 days;

        bytes32 h = keccak256(
            abi.encodePacked(
                user, address(tokenA), address(tokenB), uint256(100 ether), uint256(1000), false, expiry, secret
            )
        );

        vm.startPrank(user);
        registry.submitIntent(h, expiry);
        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, false, secret);
        tokenA.approve(address(registry), 100 ether);
        registry.depositIntentFunds(0);
        vm.stopPrank();

        registry.executeIntent(0, 1000); // price == targetPrice, greaterThan=false → should pass

        assertTrue(registry.getIntent(0).executed);
    }

    /// ONE ABOVE TARGET WITH LESS-THAN MUST REVERT
    function testExecuteOneAboveTargetLessThanReverts() public {
        uint256 expiry = block.timestamp + 1 days;

        bytes32 h = keccak256(
            abi.encodePacked(
                user, address(tokenA), address(tokenB), uint256(100 ether), uint256(1000), false, expiry, secret
            )
        );

        vm.startPrank(user);
        registry.submitIntent(h, expiry);
        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, false, secret);
        tokenA.approve(address(registry), 100 ether);
        registry.depositIntentFunds(0);
        vm.stopPrank();

        vm.expectRevert(IntentRegistry.IntentRegistry__PriceConditionNotMet.selector);
        registry.executeIntent(0, 1001);
    }

    // --------------------------
    // Event Emissions
    // --------------------------

    /// SUBMIT MUST EMIT IntentSubmitted
    function testSubmitEmitsEvent() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(user);
        vm.expectEmit(true, true, false, false);
        emit IntentRegistry.IntentSubmitted(0, user);
        registry.submitIntent(_hash(expiry), expiry);
    }

    /// REVEAL MUST EMIT IntentRevealed
    function testRevealEmitsEvent() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(user);
        registry.submitIntent(_hash(expiry), expiry);

        vm.prank(user);
        vm.expectEmit(true, false, false, false);
        emit IntentRegistry.IntentRevealed(0);
        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, true, secret);
    }

    /// DEPOSIT MUST EMIT FundsDeposited
    function testDepositEmitsEvent() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.startPrank(user);
        registry.submitIntent(_hash(expiry), expiry);
        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, true, secret);
        tokenA.approve(address(registry), 100 ether);

        vm.expectEmit(true, false, false, true);
        emit IntentRegistry.FundsDeposited(0, 100 ether);
        registry.depositIntentFunds(0);
        vm.stopPrank();
    }

    /// EXECUTE MUST EMIT IntentExecuted WITH CORRECT PRICE
    function testExecuteEmitsEvent() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.startPrank(user);
        registry.submitIntent(_hash(expiry), expiry);
        registry.revealIntent(0, address(tokenA), address(tokenB), 100 ether, 1000, true, secret);
        tokenA.approve(address(registry), 100 ether);
        registry.depositIntentFunds(0);
        vm.stopPrank();

        vm.expectEmit(true, false, false, true);
        emit IntentRegistry.IntentExecuted(0, 1001);
        registry.executeIntent(0, 1001);
    }

    // --------------------------
    // Deposit Edge Cases
    // --------------------------

    /// DEPOSIT BEFORE REVEAL IS POSSIBLE (CONTRACT ALLOWS IT — TOKENIN IS address(0))
    /// This documents current behaviour; the contract does NOT guard against it.
    function testDepositBeforeRevealUsesZeroAddress() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(user);
        registry.submitIntent(_hash(expiry), expiry);

        // tokenIn is address(0) at this point; the transferFrom call will revert
        // from the zero-address token, not from an IntentRegistry guard.
        vm.prank(user);
        vm.expectRevert(); // low-level revert from zero-address ERC20 call
        registry.depositIntentFunds(0);
    }
}
