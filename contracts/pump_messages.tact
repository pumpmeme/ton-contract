
struct FuncGasFee {
    buyTokenGasFee: Int;
    sellTokenGasFee: Int;
    wrapTokenGasFee: Int;
    newTokenGasFee: Int;
    newTokenAndBuyGasFee: Int;
    sendTokenGasFee: Int;
    sendTonGasFee: Int;
    dexCreateVault: Int;
    dexCreatePool: Int;
    dexTonDeposit: Int;
    dexTokenForwardAmount: Int;
    dexTokenDeposit: Int;
    adminCreateDex: Int;
}

struct PumpInfo {
    commonTokenTotalSupply: Int; // token total supply
    targetTonAmount: Int; // total fund ton
    availableTokenPercentage: Int; // Percentage of total tokens available for sale

    protocolFeeReceivor: Address; // fee receivor
    protocolFeePercentage: Int; // fee // 1 means 0.1% 10 means 1%
    createTokenFee: Int; // launch token fee,default 0.08 ton


    // bond curve param
    pe: Int; // dex price * ton(1), like ton(200000)
    initTonAmountLimit: Int; // the first buy tx ton limit
    signPublicKey: Int; // for sign data
}

const DUST_FACTORY: Address = address("EQBfBWT7X2BHg9tXAxzhz2aKiNTU1tpt5NsiK0uSDW_YAJ67");
const DUST_NATIVE: Int = 0b0000;
const DUST_JETTON: Int = 0b0001;
const workchain: Int = 0;
const DEX_POOL_TYPE: Int = 0;

struct TokenInfo {
    token: Address;
    wToken: Address;
    totalSupply: Int;

    // bond curve param
    targetTonAmount: Int; // total fund ton
    reserveA: Int;
    reserveT: Int;
    balanceA: Int;
    balanceT: Int;
   
    soldTokenAmount: Int;
    remainTokenAmount: Int; // remainTokenAmount + soldTokenAmount <= totalSupply
    tonBalance: Int; // the value sub fee,sub fee
    dexCreate: Bool;
    fundSuccess: Bool;

    tonVaultAddress: Address; // dex ton vault
    tokenVaultAddress: Address; // dex token vault
    tokenHash: Int; //  token address hash
}

message BuyToken {
    token: Address; // wtoken address
    minTokenAmountOut: Int;
    tgId: Int;
}

message LaunchNewToken {
    queryId: Int as uint64;
    wrapContent: Cell;
    content: Cell;
    // max_supply: Int as coins;
    tonVaultAddress: Address; // dex ton vault
    tokenVaultAddress: Address; // dex token vault
    tokenHash: Int; //  token address hash
    buyAmount: Int; // ton for buy token
    signature: Slice; // for verify data
    tgId: Int;
}


message ChangeFuncGasFee {
    buyTokenGasFee: Int;
    sellTokenGasFee: Int;
    wrapTokenGasFee: Int;
    newTokenGasFee: Int;
    newTokenAndBuyGasFee: Int;
    sendTokenGasFee: Int;
    sendTonGasFee: Int;
    dexCreateVault: Int;
    dexCreatePool: Int;
    dexTonDeposit: Int;
    dexTokenForwardAmount: Int;
    dexTokenDeposit: Int;
    adminCreateDex: Int;
}

message ChangePumpInfo {
    commonTokenTotalSupply: Int; // token total supply
    targetTonAmount: Int; // total fund ton
    availableTokenPercentage: Int = 80; // Percentage of total tokens available for sale

    protocolFeeReceivor: Address; // fee receivor
    protocolFeePercentage: Int; // fee // 1 means 0.1% 10 means 1%
    createTokenFee: Int; // for create token,default 0.08 ton

   // bond curve param
    pe: Int; // dex price * ton(1), like ton(200000)
    initTonAmountLimit: Int; // the first buy tx ton limit
    signPublicKey: Int;
    txTime: Int; // for event, ignore
}



message WithdrawProtocolFee {
    amount: Int;
}

message ChangeAdmin {
    admin: Address;
}


// message CreateDustDex {
//     wToken: Address;
//     // tokenHash: Int; // token hash
//     // tonVaultAddress: Address; // dex ton vault
//     // tokenVaultAddress: Address; // dex token vault
// }

message CreateDustDexDeposit {
    wToken: Address;
    createPool: Bool; // default false, only if failed before can set true
}


message NewTokenEvent {
    user: Address;
    token: Address;
    wToken: Address;
    tgId: Int;
    tokenTotalSupply: Int;
    targetTonAmount: Int;
    availableTokenPercentage: Int;
    txTime: Int;
}


message BuyTokenEvent {
    token: Address;
    user: Address;
    tonAmountIn: Int;
    tokenAmountOut: Int;
    tgId: Int;
    txTime: Int;
}


message WrapTokenEvent {
    token: Address;
    wToken: Address;
    user: Address;
    amount: Int;
    tgId: Int;
    txTime: Int;
}

message SellTokenEvent {
    // queryId: Int;
    tonAmountOut: Int;
    user: Address;
    token: Address;
    tokenAmountIn: Int;
    tgId: Int;
    txTime: Int;
}

message DexCreateEvent {
    token: Address;
    tonAmount: Int;
    tokenAmount: Int;
    status: Bool;
    txTime: Int;
}

message WithdrawFeeEvent {
    amount: Int;
    owner: Address;
    receivor: Address;
    txTime: Int;
}

message ChangePoolTonGoalAmountEvent {
    targetTonAmount: Int;
    txTime: Int;
}

message ChangeProtocolFeeEvent {
    protocolFeeReceivor: Address;
    protocolFeePercentage: Int;
    txTime: Int;
}