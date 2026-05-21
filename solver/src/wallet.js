import { question } from "readline-sync";

import { ethers } from "ethers";

export const getWallet = (provider) => {
  const pk = question("Private key: ", {
    hideEchoBack: true,
  });

  return new ethers.Wallet(pk, provider);
};
