import readline from "readline-sync";
import { ethers } from "ethers";

let wallet = null;

export function getWallet(provider) {
  if (wallet) return wallet;

  const pk = readline.question("Private key: ", { hideEchoBack: true });

  wallet = new ethers.Wallet(pk, provider);

  return wallet;
}
