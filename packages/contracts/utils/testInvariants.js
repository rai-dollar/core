
const BN = require('bn.js')

class TestInvariant {

  static async debtEqualsSupply(contracts) {
    const debt = await contracts.troveManager.getEntireSystemDebt(await contracts.troveManager.accumulatedRate())
    const supply = await contracts.lusdToken.totalSupply()
    return debt.eq(supply)
  }

  static async SpBalanceEqualsErc20Balance(contracts) {
    //ERC20 balance  ==  totalLUSDDeposits · P / 1e18   ± 1 wei
    const totalDeposits = await contracts.stabilityPool.getTotalLUSDDeposits()
    const balance = await contracts.lusdToken.balanceOf(contracts.stabilityPool.address)
    if (totalDeposits > balance) {
        return (totalDeposits - balance).eq(1)
    } else if (totalDeposits < balance) {
        return (balance - totalDeposits).eq(1)
    }
    return true
  }



}
module.exports = {
  TestInvariant
}
