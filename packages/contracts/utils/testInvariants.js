const testHelpers = require("../utils/testHelpers.js")
const th = testHelpers.TestHelper
const toBN = th.toBN
const BN = require('bn.js')

class TestInvariant {

  static async debtEqualsSupply(contracts) {
    const debt = await contracts.troveManager.getEntireSystemDebt(await contracts.troveManager.accumulatedRate())
    const supply = await contracts.lusdToken.totalSupply()

    return supply.sub(debt).lte(toBN('1'))

    //return debt.eq(supply)

    /*
    if (debt.gt(supply)) {
        return (debt.sub(supply)).eq(web3.utils.toBN('1'))
    } else if (debt.lt(supply)) {
        return (supply.sub(debt)).eq(web3.utils.toBN('1'))
    }
    return true
    */
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
