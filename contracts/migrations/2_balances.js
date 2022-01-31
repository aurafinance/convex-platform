// cDAI/cUSDC
const cDAIcUSDCAccount = "0x3d8d742ee7fbc497ae671528a19a1489ba204482";
const cDAIcUSDCAddress = "0x845838DF265Dcd2c412A1Dc9e959c7d08537f8a2";

const IERC20 = artifacts.require("IERC20");

module.exports = async function (deployer, network, accounts) {
  const cDAIcUSDC = await IERC20.at(cDAIcUSDCAddress);

  const balance = await cDAIcUSDC.balanceOf(cDAIcUSDCAccount);
  console.log("cDAI/cUSDC whale balance:", balance.toString());

  for (const account of accounts) {
    const amount = balance.div(new web3.utils.BN(accounts.length.toString()));
    await cDAIcUSDC.transfer(account, amount, { from: cDAIcUSDCAccount });
    const newBalance = await cDAIcUSDC.balanceOf(account);
    console.log(`cDAI/cUSDC ${account} balance:`, newBalance.toString());
  }
};
