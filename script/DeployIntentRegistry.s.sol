// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {IntentRegistry} from "../src/IntentRegistry.sol";

contract DeployIntentRegistry is Script {
    function deploy(address router) public returns (IntentRegistry) {
        vm.startBroadcast();

        IntentRegistry registry = new IntentRegistry(router);

        vm.stopBroadcast();

        return registry;
    }

    function run() external {
        address router = vm.parseAddress(vm.prompt("Router address"));

        deploy(router);
    }
}
