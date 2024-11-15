import "@stdlib/deploy";
import "@stdlib/ownable";
import "./token";
import "./jetton";
import "./jetton_messages";
import "./pump_messages";
import "./pump_errors";

contract PumpCore with Deployable,Ownable{

     /* enough for 1 KB of storage for 2.5 years */
    const MIN_TON_FOR_STORAGE: Int = ton("0.1");
    // const MIN_TON_VALUE: Int = ton("0.01");

    const PRECISION: Int = 1000000000; // Using 10^9 as precision

    funcGasFee: FuncGasFee; // call method gas fee
    pumpInfo: PumpInfo; // pump info param
    totalProtocolFee: Int; // protocol fee, can withdraw by owner
    totalDexCreateFee: Int; // dex create cost

    tokenCounter: Int = 0; // how much token
    tokenCounterMap: map<Int,Address>; // idx -> w-tokenAddress
    tokenInfoMap: map<Address,TokenInfo>;
    tokenWalletMap: map<Address,Address>; // store pumpCore jettton wallet address

    owner: Address;
    admin: Address;

    init(protocolFeeReceivor: Address,protocolFeePercentage: Int,targetTonAmount: Int,signPublicKey: Int) {
        self.owner = sender();
        self.admin = sender();

        self.totalProtocolFee = 0;
        self.totalDexCreateFee = 0;
        // self.pumpLogAddress = pumpLogAddress;

        self.funcGasFee = FuncGasFee {
            buyTokenGasFee: ton("0.1"),
            // sell transfer fee from user
            sendTonGasFee:  ton("0.02"),
            sellTokenGasFee: ton("0.1"),
            wrapTokenGasFee: ton("0.1"),
            newTokenGasFee:  ton("0.2"), // less 0.07 ton with newTokenAndBuyGasFee
            newTokenAndBuyGasFee:  ton("0.27"),
            sendTokenGasFee: ton("0.05"),
            dexCreateVault: ton("0.1"),
            dexCreatePool: ton("0.25"),
            dexTonDeposit: ton("0.3"),
            dexTokenForwardAmount: ton("0.4"),
            dexTokenDeposit: ton("0.5"),
            adminCreateDex: ton("0.05"),
        };


        self.pumpInfo = PumpInfo {
            commonTokenTotalSupply: ton("1000000000"),  // 1 billion token total supply
            // targetTonAmount:  ton("10"),
            targetTonAmount: targetTonAmount,
            availableTokenPercentage:  80,  // Percentage of total tokens available for sale

            protocolFeeReceivor: protocolFeeReceivor,
            protocolFeePercentage: protocolFeePercentage,

            createTokenFee: ton("0.08"),
            initTonAmountLimit: targetTonAmount / 10,
            pe: 0,
            signPublicKey: signPublicKey,
        };

        let p: Int =  ton("1");
        let A: Int = self.pumpInfo.commonTokenTotalSupply * self.pumpInfo.availableTokenPercentage / 100;
        let T: Int = self.pumpInfo.targetTonAmount;
        let pe: Int = (self.pumpInfo.commonTokenTotalSupply - A) * p / T;
        self.pumpInfo.pe = pe;

    }

    // default method ,allow transfer ton to contract
    // for owner transfer ton for storage ton fee
    receive() {
        let ctx: Context = context();
        self.requireOwner();
    }

    // buy token
    receive(msg: BuyToken) {
        // methodId: 0xbe4b8dc9
        let ctx: Context = context();
        let tokenInfoNull: TokenInfo? = self.tokenInfoMap.get(msg.token);

        // Check if token exists and is valid
        nativeThrowUnless(INVALID_WTOKEN, tokenInfoNull != null);
        nativeThrowUnless(INVALID_FUND, !tokenInfoNull!!.fundSuccess);

        let tokenInfo: TokenInfo = tokenInfoNull!!;
        let tonAmount: Int = ctx.value - self.funcGasFee.buyTokenGasFee;
        nativeThrowUnless(INSUFFICIENT_TON_AMOUNT, tonAmount >= ton("0.1"));

        let jettonWalletAddress: Address = self.jettonWalletAddress(myAddress(), msg.token);
        let buyFee = tonAmount * self.pumpInfo.protocolFeePercentage / 1000;
        let refundTonAmount: Int = 0;
        // Handle the last buy transaction,refund other ton
        if (tokenInfo.tonBalance + tonAmount - buyFee >= tokenInfo.targetTonAmount) {
             let needTonAmount: Int = tokenInfo.targetTonAmount - tokenInfo.tonBalance;
             let realNeedTonAmount = needTonAmount * 1000 / (1000 - self.pumpInfo.protocolFeePercentage);
             refundTonAmount  = tonAmount - realNeedTonAmount;
             tonAmount = realNeedTonAmount;
             buyFee = tonAmount * self.pumpInfo.protocolFeePercentage / 1000;
        }

        tonAmount -= buyFee;
        let tokenAmount: Int = self.getAmountOut(tonAmount, tokenInfo.reserveT, tokenInfo.reserveA);

        // Check for slippage
        nativeThrowUnless(INSUFFICIENT_TOKEN_OUT, tokenAmount >= msg.minTokenAmountOut);
        // refund other ton
        if(refundTonAmount >= ton("0.02")) {
            self.refundTon(ctx.sender, refundTonAmount);
        }

        // Adjust token amount if necessary
        // tokenAmount = self.adjustSoldTokenAmount(tokenInfo, tokenAmount);

         // Update token info
        tokenInfo.balanceA -= tokenAmount;
        tokenInfo.balanceT += tonAmount;
        tokenInfo.reserveA -= tokenAmount;
        tokenInfo.reserveT += tonAmount;

        self.totalProtocolFee += buyFee; // update fee
        tokenInfo.soldTokenAmount += tokenAmount; // sold token amount
        tokenInfo.tonBalance += tonAmount; // sub fee

        self.tokenInfoMap.set(msg.token, tokenInfo);
        self.sendTokens(jettonWalletAddress, ctx.sender, tokenAmount);

        emit(BuyTokenEvent {
            token: msg.token,
            user: ctx.sender,
            tonAmountIn: tonAmount,
            tokenAmountOut: tokenAmount,
            tgId: msg.tgId,
            txTime: now()
        }.toCell());

        // Check if funding is successful
        if (tokenInfo.tonBalance + ton("0.1") > tokenInfo.targetTonAmount) {
            self.finalizeFunding(tokenInfo,ctx.sender);
        }
    }

    // Helper function to refund
    fun refundTon(to: Address, amount: Int) {
        send(SendParameters {
            to: to,
            value: amount,
            mode: SendPayGasSeparately
        });
    }


    // Adjust sold token amount if necessary
    // fun adjustSoldTokenAmount(tokenInfo: TokenInfo, tokenAmount: Int): Int {
    //     if ((tokenInfo.soldTokenAmount + tokenAmount) > (self.pumpInfo.commonTokenTotalSupply * self.pumpInfo.availableTokenPercentage / 100)) {
    //         tokenAmount = self.pumpInfo.commonTokenTotalSupply * self.pumpInfo.availableTokenPercentage / 100 - tokenInfo.soldTokenAmount;
    //     }
    //     return tokenAmount;
    // }

    // Finalize funding
    fun finalizeFunding(tokenInfo: TokenInfo,sender: Address) {
        tokenInfo.fundSuccess = true;
        let leftToken: Int = self.pumpInfo.commonTokenTotalSupply * self.pumpInfo.availableTokenPercentage / 100 - tokenInfo.soldTokenAmount;
        tokenInfo.remainTokenAmount += leftToken;
        self.tokenInfoMap.set(tokenInfo.wToken, tokenInfo);
        self.createDexPool(tokenInfo, sender);
    }

    receive(msg: CreateDustDexDeposit) {
        // methodId: 0xf2cae70c
        let ctx: Context = context();
        nativeThrowUnless(INVALID_CALLER, ctx.sender == self.admin);
        nativeThrowUnless(INSUFFICIENT_GAS, ctx.value >= self.funcGasFee.adminCreateDex);
        let tokenInfoNull: TokenInfo? = self.tokenInfoMap.get(msg.wToken);
        nativeThrowUnless(WTOKEN_NOT_EXIST, tokenInfoNull != null);
        let tokenInfo: TokenInfo = tokenInfoNull!!;
        nativeThrowUnless(ERROR_FUND_STATUS, tokenInfo.fundSuccess);

        let asset0 = beginCell()
                .storeUint(DUST_NATIVE,4)
                .asSlice();

        let asset1 = beginCell()
                .storeUint(DUST_JETTON, 4)
                .storeUint(workchain, 8)  // Use workChain() method
                .storeUint(tokenInfo.tokenHash, 256)  // Convert Address to Uint256
                .asSlice();

        if(msg.createPool) {
            self.createVault(asset1);
            self.createPool(asset0, asset1);

            let dexCostTon = self.funcGasFee.dexCreateVault + self.funcGasFee.dexCreatePool;
            self.totalDexCreateFee += dexCostTon;
            return;
        }


        self.depositTon(asset0, asset1,tokenInfo, tokenInfo.tonBalance, tokenInfo.remainTokenAmount);
        self.depositToken(asset0, asset1,tokenInfo,  tokenInfo.tonBalance, tokenInfo.remainTokenAmount);

        tokenInfo.dexCreate = true;
        self.tokenInfoMap.set(tokenInfo.wToken, tokenInfo);

        let dexCostTon = self.funcGasFee.dexTonDeposit + self.funcGasFee.dexTokenDeposit;
        self.totalDexCreateFee += dexCostTon;
        emit(DexCreateEvent {
            token: tokenInfo.token,
            tonAmount: tokenInfo.tonBalance,
            tokenAmount: tokenInfo.remainTokenAmount,
            status: true,
            txTime: now()
        }.toCell());

    }


    // New helper function to create vault and pool
    fun createDexPool(tokenInfo: TokenInfo, sender: Address) {
        // let tokenAddress: Address = tokenInfo.token;
        // let tokenDepositAmount: Int = tokenInfo.remainTokenAmount;
        // let tonDepositAmount: Int = tokenInfo.tonBalance;
        // tokenInfo.dexCreate = true;

        let asset0 = beginCell()
                .storeUint(DUST_NATIVE,4)
                .asSlice();

        let asset1 = beginCell()
                .storeUint(DUST_JETTON, 4)
                .storeUint(workchain, 8)  // Use workChain() method
                .storeUint(tokenInfo.tokenHash, 256)  // Convert Address to Uint256
                .asSlice();

        // Create vault and pool
        self.createVault(asset1);
        self.createPool(asset0, asset1);

        let dexCostTon = self.funcGasFee.dexCreateVault + self.funcGasFee.dexCreatePool;
        self.totalDexCreateFee += dexCostTon;
        emit(DexCreateEvent {
            token: tokenInfo.token,
            tonAmount: tokenInfo.tonBalance,
            tokenAmount: tokenInfo.remainTokenAmount,
            status: false,
            txTime: now()
        }.toCell());

        // Deposit ton and token
        // self.depositTon(asset0, asset1,tokenInfo, tokenInfo.tonBalance, tokenInfo.remainTokenAmount);
        // self.depositToken(asset0, asset1,tokenInfo, tokenInfo.tonBalance, tokenInfo.remainTokenAmount, sender);
    }

    // New helper function to create vault
    fun createVault(asset1: Slice) {
        let create_vault_body = beginCell()
                .storeUint(567271467, 32)
                .storeUint(1, 64) // query_id
                .storeSlice(asset1)
                .endCell();

        send(SendParameters{
                to: DUST_FACTORY,
                body: create_vault_body,
                value:  self.funcGasFee.dexCreateVault,
                mode: SendPayGasSeparately + SendIgnoreErrors,
        });
    }

    // New helper function to create pool
    fun createPool(asset0: Slice, asset1: Slice) {
        let create_pool_body = beginCell()
                .storeUint(2547326767, 32)
                .storeUint(2, 64) // query_id
                .storeSlice(asset0)
                .storeSlice(asset1)
                .endCell();

        send(SendParameters{
                to: DUST_FACTORY,
                body: create_pool_body,
                value:  self.funcGasFee.dexCreatePool,
                mode: SendPayGasSeparately + SendIgnoreErrors,
        });
    }

    // New helper function to deposit ton
    fun depositTon(asset0: Slice, asset1: Slice,tokenInfo: TokenInfo, tonDepositAmount: Int, tokenDepositAmount: Int) {
        let ton_deposit_body = beginCell()
                .storeUint(0xd55e4686, 32)
                .storeUint(3, 64) // query_id
                .storeCoins(tonDepositAmount)
                .storeUint(DEX_POOL_TYPE, 1)
                .storeSlice(asset0)
                .storeSlice(asset1)
                .storeUint(3, 2)
                .storeRef(
                    beginCell()
                    .storeCoins(1) // minimalLPAmount
                    .storeCoins(tonDepositAmount)
                    .storeCoins(tokenDepositAmount)
                .endCell()
                )
                .storeRef(beginCell().endCell())
                .storeRef(beginCell().endCell())
                .endCell();

        send(SendParameters{
                to: tokenInfo.tonVaultAddress,
                body: ton_deposit_body,
                value: self.funcGasFee.dexTonDeposit + tonDepositAmount,
                mode: SendPayGasSeparately + SendIgnoreErrors
        });
    }

    fun depositToken(asset0: Slice, asset1: Slice,tokenInfo: TokenInfo, tonDepositAmount: Int, tokenDepositAmount: Int) {
         let token_payload =
                beginCell()
                .storeUint(0x40e108d6, 32)
                .storeUint(DEX_POOL_TYPE, 1)
                .storeSlice(asset0)
                .storeSlice(asset1)
                .storeCoins(1)
                .storeCoins(tonDepositAmount)
                .storeCoins(tokenDepositAmount)
                .storeUint(0, 2)
                .endCell();

            let jetton_body = beginCell()
                .storeUint(260734629, 32)
                .storeUint(4, 64) // query_id
                .storeCoins(tokenDepositAmount)
                .storeAddress(tokenInfo.tokenVaultAddress)
                // .storeAddress(sender)
                .storeAddress(newAddress(0,0))
                .storeBool(false) // no custom payload
                .storeCoins(self.funcGasFee.dexTokenForwardAmount) // forward amount
                .storeBool(true) // we store forwardPayload as a referance
                .storeRef(token_payload)
                .endCell();

            // let tokenAddress: Address = newAddress(workchain,msg.tokenHash);
            let tokenWalletInit: StateInit = initOf JettonDefaultWallet(myAddress(), tokenInfo.token);

            send(SendParameters{
                to: contractAddress(tokenWalletInit),
                body: jetton_body,
                value: self.funcGasFee.dexTokenDeposit,
                mode: SendPayGasSeparately + SendIgnoreErrors,
            });
    }



    // jetton token transfer notify
    // sell token enter
    // @msg.from user address
    // @sender pumpCore jetton wallet
    // @msg.amount transfer token amount
    receive(msg: TokenNotification) {
        // methodId: 0x7362d09c
        let ctx: Context = context();
        // dump(msg.forward_payload.bits());
        nativeThrowUnless(INVALID_INPUT_PARAMS, msg.forward_payload.bits() >= 16);
        msg.forward_payload.loadUint(0);
        let op: Int = msg.forward_payload.loadUint(1);


        // Check gas fee based on operation type
        let requiredGasFee: Int = (op == 0) ? self.funcGasFee.wrapTokenGasFee : self.funcGasFee.sellTokenGasFee;
        nativeThrowUnless(INSUFFICIENT_GAS, ctx.value >= requiredGasFee);

        let minTonAmountOut: Int = msg.forward_payload.loadCoins();
        let tgId: Int = msg.forward_payload.loadCoins();
        let tokenExistMap = self.tokenWalletMap.get(ctx.sender);

        // Handle case where token does not exist
        if (tokenExistMap == null) {
            self.sendTokens(ctx.sender,msg.from,msg.amount);
            return;
        }

        let wJetton = tokenExistMap!!;
        // let jettonWalletAddress: Address = ctx.sender;
        let tokenInfoNull: TokenInfo? = self.tokenInfoMap.get(wJetton);
        nativeThrowUnless(INVALID_WTOKEN, tokenInfoNull != null);

        // Handle fund success but dex not created
        if (tokenInfoNull!!.fundSuccess && !tokenInfoNull!!.dexCreate) {
            self.sendTokens(ctx.sender, msg.from,msg.amount);
            return;
        }

        // Handle token already created dex
        if (tokenInfoNull != null && tokenInfoNull!!.dexCreate) {
            if (op == 0) {
                self.wrapToken(msg.amount, tokenInfoNull!!.token, msg.from, wJetton,tgId);
            } else {
               self.sendTokens(ctx.sender, msg.from,msg.amount);
            }
            return;
        }

        let tokenInfo: TokenInfo = tokenInfoNull!!;
        let tonAmountOut: Int = self.getAmountOut(msg.amount, tokenInfo.reserveA, tokenInfo.reserveT);

        let sellTonFee = tonAmountOut * self.pumpInfo.protocolFeePercentage / 1000;
        tonAmountOut -= sellTonFee;

        // Check for slippage
        if (tonAmountOut < minTonAmountOut) {
            self.sendTokens(ctx.sender, msg.from, msg.amount);
            return;
        }

        // Update token info
        tokenInfo.balanceA += msg.amount;
        tokenInfo.balanceT -= tonAmountOut;
        tokenInfo.reserveA += msg.amount;
        tokenInfo.reserveT -= tonAmountOut;

        self.totalProtocolFee += sellTonFee; // update fee
        tokenInfo.soldTokenAmount -= msg.amount;
        tokenInfo.tonBalance -= tonAmountOut + sellTonFee;
        self.tokenInfoMap.set(wJetton, tokenInfo);

        emit(SellTokenEvent{
            tonAmountOut: tonAmountOut,
            user: msg.from,
            token: wJetton,
            tokenAmountIn: msg.amount,
            tgId: tgId,
            txTime: now()
        }.toCell());

        // Send ton to user
        send(SendParameters{
            to: msg.from,
            value: tonAmountOut + self.funcGasFee.sendTonGasFee,
            mode: SendPayGasSeparately
        });
    }


    // New helper function to wrap token
    fun wrapToken(amount: Int, tokenAddress: Address, msgFrom: Address, wToken: Address,tgId: Int) {
        emit(WrapTokenEvent{
            token: tokenAddress,
            wToken: wToken,
            user: msgFrom,
            amount: amount,
            tgId: tgId,
            txTime: now()
        }.toCell());

        let jettonWalletAddress2 = self.jettonWalletAddress(myAddress(), tokenAddress);
        send(SendParameters{
            to: jettonWalletAddress2,
            body: TokenTransfer{
                query_id: 0,
                amount: amount,
                to: msgFrom,
                response_destination: null,
                forward_ton_amount: 0,
                forward_payload: emptySlice()
            }.toCell(),
            value: self.funcGasFee.sendTokenGasFee,
            mode: SendPayGasSeparately,
        });
    }


    // launch token
    receive(msg: LaunchNewToken){
        // methodId: 0xec43e78d
        let ctx: Context = context();
        let fee: Int = self.funcGasFee.newTokenGasFee + self.pumpInfo.createTokenFee;
        if(msg.buyAmount > 0) {
            fee = self.funcGasFee.newTokenAndBuyGasFee + self.pumpInfo.createTokenFee;
        }
        nativeThrowUnless(INSUFFICIENT_GAS, ctx.value >= fee + msg.buyAmount);
        let buyAmount = msg.buyAmount;
        nativeThrowUnless(EXCEED_BUY_AMOUNT, buyAmount <= self.pumpInfo.initTonAmountLimit);

        // Deploy tokens
        let tokenInit: StateInit = self.deployToken(msg.wrapContent);
        let tokenInit2: StateInit = self.deployToken(msg.content);
        let wrapTokenAddress: Address = contractAddress(tokenInit);
        let tokenInfoNull: TokenInfo? = self.tokenInfoMap.get(wrapTokenAddress);
        nativeThrowUnless(CREATE_TOKEN_EXIST, tokenInfoNull == null);
        let tokenAddress: Address = contractAddress(tokenInit2);

        // Check signature
        let refData = beginCell()
            .storeAddress(tokenAddress)
            .storeAddress(wrapTokenAddress)
            .endCell();

        let data = beginCell()
            .storeRef(refData)
            .storeAddress(msg.tonVaultAddress)
            .storeAddress(msg.tokenVaultAddress)
            .storeUint(msg.tokenHash,256)
            .endCell();
        let hash: Int = data.hash();
        let signCheck: Bool = checkSignature(hash, msg.signature, self.pumpInfo.signPublicKey);
        nativeThrowUnless(SIGN_FAILED, signCheck);

        // TODO check vault address is right
        let tokenInfo: TokenInfo = self.createTokenInfo(tokenAddress, wrapTokenAddress, ctx.sender, buyAmount,msg.tonVaultAddress,msg.tokenVaultAddress,msg.tokenHash);
        let initBuyTokenAmount: Int = 0;
        if(buyAmount > 0) {
            let tonFee = buyAmount * self.pumpInfo.protocolFeePercentage / 1000;
            buyAmount -= tonFee;
            let tokenAmount: Int =  self.getAmountOut(buyAmount, tokenInfo.reserveT, tokenInfo.reserveA);

            tokenInfo.balanceA -= tokenAmount;
            tokenInfo.balanceT += buyAmount;
            tokenInfo.reserveA -= tokenAmount;
            tokenInfo.reserveT += buyAmount;


            tokenInfo.soldTokenAmount += tokenAmount;
            self.totalProtocolFee += tonFee; // update fee
            initBuyTokenAmount = tokenAmount;
            tokenInfo.tonBalance = buyAmount;
        }

         // new token event
        emit(NewTokenEvent{
            user: ctx.sender,
            token: tokenAddress,
            wToken: wrapTokenAddress,
            tgId: msg.tgId,
            tokenTotalSupply: self.pumpInfo.commonTokenTotalSupply,
            targetTonAmount: self.pumpInfo.targetTonAmount,
            availableTokenPercentage: self.pumpInfo.availableTokenPercentage,
            txTime: now()}.toCell());

         // Mint tokens to this contract
        self.mintTokens(tokenAddress, ton("0.05"),tokenInit2);
        if (initBuyTokenAmount > 0) {
            self.mintTokensByPump(wrapTokenAddress, ton("0.12"),tokenInit,ctx.sender,initBuyTokenAmount);
            tokenInfo.soldTokenAmount = initBuyTokenAmount;
            // tx event
            emit(BuyTokenEvent{
                token: wrapTokenAddress,
                user: ctx.sender,
                tonAmountIn: buyAmount,
                tokenAmountOut: initBuyTokenAmount,
                tgId: msg.tgId,
                txTime: now()}.toCell());

        }else {
            self.mintTokens(wrapTokenAddress, ton("0.05"),tokenInit);
        }

        // Store token information
        self.tokenInfoMap.set(wrapTokenAddress, tokenInfo);
        self.tokenCounter += 1;
        self.tokenCounterMap.set(self.tokenCounter, wrapTokenAddress);
        self.totalProtocolFee += self.pumpInfo.createTokenFee; // add fee
        self.tokenWalletMap.set(self.jettonWalletAddress(myAddress(), wrapTokenAddress), wrapTokenAddress);
    }

    // New helper function to deploy a token
    fun deployToken(content: Cell): StateInit {
        let tokenInit: StateInit = initOf Token(myAddress(), content, self.pumpInfo.commonTokenTotalSupply);
        return tokenInit;
    }

    // New helper function to mint tokens
    fun mintTokens(tokenAddress: Address, value: Int,tokenInit: StateInit) {
        send(SendParameters{
            to: tokenAddress,
            body: MintAll{receiver: myAddress()}.toCell(),
            value: value,
            mode: SendPayGasSeparately,
            code: tokenInit.code,
            data: tokenInit.data
        });
    }

    fun mintTokensByPump(tokenAddress: Address, value: Int,tokenInit: StateInit,initBuyer: Address,initBuyAmunt: Int) {
        send(SendParameters{
            to: tokenAddress,
            body: MintByPump{owner: myAddress(), receiver: initBuyer,receiverAmount: initBuyAmunt}.toCell(),
            value: value,
            mode: SendPayGasSeparately,
            code: tokenInit.code,
            data: tokenInit.data
        });
    }


    // New helper function to create token info
    fun createTokenInfo(tokenAddress: Address, wrapTokenAddress: Address, sender: Address, buyAmount: Int,tonVaultAddress: Address,tokenVaultAddress: Address,tokenHash: Int): TokenInfo {
        let p: Int =  ton("1");
        let A: Int = self.pumpInfo.commonTokenTotalSupply * self.pumpInfo.availableTokenPercentage / 100;
        let T: Int = self.pumpInfo.targetTonAmount;
        let pe: Int = self.pumpInfo.pe;

        nativeThrowUnless(INVALID_PE, A * p > T * pe); // A CAN NOT <= T * Pe
        // self.pumpInfo.pe = pe;
        let t: Int = T * A / (A - T * pe / p);
        // let k: Int = Pe * t * t;
        let a: Int = pe * t / p;

        return TokenInfo{
            token: tokenAddress,
            wToken: wrapTokenAddress,
            targetTonAmount: self.pumpInfo.targetTonAmount,
            totalSupply: self.pumpInfo.commonTokenTotalSupply,
            soldTokenAmount: 0,
            remainTokenAmount: self.pumpInfo.commonTokenTotalSupply * (100 - self.pumpInfo.availableTokenPercentage) / 100,
            tonBalance: 0,
            reserveA: a + A,
            reserveT: t - T,
            balanceA: A,
            balanceT: 0,
            dexCreate: false,
            fundSuccess: false,
            tonVaultAddress: tonVaultAddress,
            tokenVaultAddress: tokenVaultAddress,
            tokenHash: tokenHash,

        };
    }

     // change gas fee
    receive(msg: ChangeFuncGasFee) {
        self.requireOwner();
        self.funcGasFee = FuncGasFee {
            buyTokenGasFee: msg.buyTokenGasFee,
            sellTokenGasFee: msg.sellTokenGasFee,
            wrapTokenGasFee: msg.wrapTokenGasFee,
            newTokenGasFee: msg.newTokenGasFee,
            newTokenAndBuyGasFee: msg.newTokenAndBuyGasFee,
            sendTokenGasFee: msg.sendTokenGasFee,
            sendTonGasFee: msg.sendTonGasFee,
            dexCreateVault: msg.dexCreateVault,
            dexCreatePool: msg.dexCreatePool,
            dexTonDeposit: msg.dexTonDeposit,
            dexTokenForwardAmount:msg.dexTokenForwardAmount,
            dexTokenDeposit: msg.dexTokenDeposit,
            adminCreateDex: msg.adminCreateDex,
        };
    }


    // withdraw protocol fee
    receive(msg: WithdrawProtocolFee) {
        self.requireOwner();
        nativeThrowUnless(INVALID_INPUT_PARAMS, msg.amount <= self.totalProtocolFee);
        nativeThrowUnless(INSUFFICIENT_CONTRACT_BALANCE, myBalance() - msg.amount >= self.MIN_TON_FOR_STORAGE);
        self.totalProtocolFee -= msg.amount;

        // log
        emit(WithdrawFeeEvent{amount: msg.amount, owner: self.owner,receivor:self.pumpInfo.protocolFeeReceivor, txTime: now()}.toCell());

        // send ton
        send(SendParameters{
            to: self.pumpInfo.protocolFeeReceivor,
            value: msg.amount,
            mode: SendPayGasSeparately
        });

    }


    receive(msg: ChangeAdmin) {
        self.requireOwner();
        self.admin = msg.admin;
    }

    // change pump info param
    receive(msg: ChangePumpInfo) {
        self.requireOwner();
        nativeThrowUnless(INVALID_INPUT_PARAMS,msg.protocolFeePercentage > 0);
        nativeThrowUnless(INVALID_INPUT_PARAMS,msg.protocolFeePercentage < 1000);
        nativeThrowUnless(INVALID_INPUT_PARAMS,msg.availableTokenPercentage > 0);
        nativeThrowUnless(INVALID_INPUT_PARAMS,msg.availableTokenPercentage < 100);

        let p: Int =  ton("1");
        let A: Int = msg.commonTokenTotalSupply * msg.availableTokenPercentage / 100;
        let T: Int = msg.targetTonAmount;
        let pe: Int = (msg.commonTokenTotalSupply - A) * p / T;

        self.pumpInfo = PumpInfo {
            commonTokenTotalSupply: msg.commonTokenTotalSupply,
            targetTonAmount:  msg.targetTonAmount,
            availableTokenPercentage:  msg.availableTokenPercentage,

            protocolFeeReceivor: msg.protocolFeeReceivor,
            protocolFeePercentage: msg.protocolFeePercentage,

            createTokenFee: msg.createTokenFee,
            pe: pe,
            initTonAmountLimit: msg.initTonAmountLimit,// the first buy tx ton limit
            signPublicKey: msg.signPublicKey,
        };
        msg.txTime = now();
        emit(msg.toCell());
    }

    // return null mean token not exist
    get fun tokenInfo(_token: Address): TokenInfo {
        let sender = sender();
        let res: TokenInfo? = self.tokenInfoMap.get(_token);
        if (res == null) {
            return TokenInfo {
                token: sender,
                wToken: sender,
                targetTonAmount: 0,
                totalSupply: 0,
                soldTokenAmount: 0,
                remainTokenAmount: 0,
                tonBalance: 0,
                reserveA: 0,
                reserveT: 0,
                balanceA: 0,
                balanceT: 0,
                dexCreate: false,
                fundSuccess: false,
                tonVaultAddress: sender,
                tokenVaultAddress: sender,
                tokenHash: 0,
            }
        }
        return res!!;
    }

    get fun tokenCounter(): Int {
        return self.tokenCounter;
    }

    get fun tokenAddress(_counter: Int): Address? {
        _counter = min(_counter,self.tokenCounter);
        return self.tokenCounterMap.get(_counter);
    }

    get fun calTokenAddress(content: Cell): Address {
        let init: StateInit =  initOf Token(myAddress(), content, self.pumpInfo.commonTokenTotalSupply);
        return contractAddress(init)
    }

    get fun jettonWalletAddress(user: Address,token: Address): Address {
        let init: StateInit = initOf JettonDefaultWallet(user, token);
        return contractAddress(init);
    }

    get fun protocolFeeReceivor(): Address {
        return self.pumpInfo.protocolFeeReceivor;
    }

    get fun protocolFeePercentage(): Int {
        return self.pumpInfo.protocolFeePercentage;
    }

    get fun createTokenFee(): Int {
        return self.pumpInfo.createTokenFee;
    }

    get fun gasFee(): FuncGasFee {
        return self.funcGasFee;
    }

    get fun targetTonAmount(): Int {
        return self.pumpInfo.targetTonAmount;
    }

    get fun admin(): Address {
        return self.admin;
    }


    get fun pumpInfo(): PumpInfo {
        return self.pumpInfo;
    }

    get fun checkLaunchTokenSignature(tokenAddress: Address,wrapTokenAddress: Address,tonVaultAddress: Address,tokenVaultAddress: Address,tokenHash: Int,signature: Slice): Bool {
        let refData = beginCell()
            .storeAddress(tokenAddress)
            .storeAddress(wrapTokenAddress)
            .endCell();

        let data = beginCell()
            .storeRef(refData)
            .storeAddress(tonVaultAddress)
            .storeAddress(tokenVaultAddress)
            .storeUint(tokenHash,256)
            .endCell();
        let hash: Int = data.hash();
        return checkSignature(hash, signature, self.pumpInfo.signPublicKey);
    }



    get fun purchaseReturn(tokenAddress: Address,tonAmount: Int): Int {
        let tokenInfoNull: TokenInfo? = self.tokenInfoMap.get(tokenAddress);
        if(tokenInfoNull == null || tokenInfoNull!!.dexCreate) {
            return -1;
        }
        let tokenInfo: TokenInfo = tokenInfoNull!!;
        tonAmount = min(tokenInfo.targetTonAmount - tokenInfo.tonBalance,tonAmount);
        let fee = tonAmount * self.pumpInfo.protocolFeePercentage / 1000;
        tonAmount -= fee;

        return self.getAmountOut(tonAmount, tokenInfo.reserveT, tokenInfo.reserveA);

    }

    get fun saleReturn(tokenAddress: Address,tokenAmount: Int): Int {
        let tokenInfoNull: TokenInfo? = self.tokenInfoMap.get(tokenAddress);
        if(tokenInfoNull == null || tokenInfoNull!!.dexCreate) {
            return -1;
        }
        let tokenInfo: TokenInfo = tokenInfoNull!!;
        tokenAmount = min(tokenInfo.soldTokenAmount,tokenAmount);

        let tonOut: Int = self.getAmountOut(tokenAmount, tokenInfo.reserveA, tokenInfo.reserveT);
        let fee = tonOut * self.pumpInfo.protocolFeePercentage / 1000;

        return tonOut - fee;
    }

    get fun currentTokenPrice(tokenAddress: Address): Int {
        let tokenInfoNull: TokenInfo? = self.tokenInfoMap.get(tokenAddress);
        if(tokenInfoNull == null || tokenInfoNull!!.dexCreate) {
            return -1;
        }

        let tokenInfo: TokenInfo = tokenInfoNull!!;
        return self.PRECISION * tokenInfo.reserveT / tokenInfo.reserveA
    }

    get fun totalProtocolFee(): Int {
        return self.totalProtocolFee;
    }

    get fun totalDexCreateFee(): Int {
        return self.totalDexCreateFee;
    }

    fun sendTokens(jettonWalletAddress: Address,to: Address, amount: Int) {
        // dump(jettonWalletAddress);
        // dump(to);
        send(SendParameters{
            to: jettonWalletAddress,
            body: TokenTransfer{
                query_id: 0,
                amount: amount,
                to: to,
                response_destination: to,
                forward_ton_amount: 0,
                forward_payload: emptySlice()
            }.toCell(),
            value: self.funcGasFee.sendTokenGasFee,
            mode: SendPayGasSeparately,
        });
    }


    fun getAmountOut(amountIn: Int, reserveIn: Int, reserveOut: Int): Int {
        nativeThrowUnless(INVALID_INPUT_AMOUNT, amountIn > 0);
        nativeThrowUnless(INSUFFICIENT_LIQUIDITY, reserveIn > 0 && reserveOut > 0);
        let numerator: Int = amountIn * reserveOut;
        let denominator: Int = reserveIn + amountIn;
        return numerator / denominator;
    }

    fun getAmountIn(amountOut: Int, reserveIn: Int, reserveOut: Int): Int {
        nativeThrowUnless(INVALID_OUTPUT_AMOUNT, amountOut > 0);
        nativeThrowUnless(INSUFFICIENT_LIQUIDITY, reserveIn > 0 && reserveOut > 0);
        let numerator: Int = reserveIn * amountOut;
        let denominator: Int = reserveOut - amountOut;
        return (numerator / denominator) + 1;
    }

}


