// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {DeployIntentRegistry} from "../../script/DeployIntentRegistry.s.sol";
import {IntentRegistry} from "../../src/IntentRegistry.sol";

contract DeployIntentRegistryTest is Test {
    DeployIntentRegistry internal deployer;

    address internal constant ROUTER =
        address(0x1234567890123456789012345678901234567890);

    function setUp() public {
        deployer = new DeployIntentRegistry();
    }

    /// DEPLOYMENT MUST SET ROUTER CORRECTLY
    function testDeploySetsRouter() public {
        IntentRegistry registry = deployer.deploy(ROUTER);

        assertEq(address(registry.ROUTER()), ROUTER);
    }

    /// DEPLOYMENT MUST RETURN VALID CONTRACT
    function testDeployReturnsContract() public {
        IntentRegistry registry = deployer.deploy(ROUTER);

        assertTrue(address(registry) != address(0));
    }

    /// DEPLOYED CONTRACT MUST START CLEAN
    function testDeployInitialState() public {
        IntentRegistry registry = deployer.deploy(ROUTER);

        assertEq(registry.nextIntentId(), 0);
    }

    // function testRunDeploys() public {
    //     vm.setEnv("ROUTER", vm.toString(ROUTER));

    //     deployer.run();
    // }
}
