const hre = require("hardhat");

async function main() {
  // const router = "0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3"; // UniswapV2Router02 address
  // const weth = "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9";
  // 
  const router = "0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3"; // UniswapV2Router02 address
  const weth = "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9";   // WETH address on the same network

  const SwapAllToETH = await hre.ethers.getContractFactory("SwapAllToETH");
  const swapper = await SwapAllToETH.deploy(router, weth);

  await swapper.waitForDeployment();

console.log(`Contract deployed to: ${await swapper.getAddress()}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
