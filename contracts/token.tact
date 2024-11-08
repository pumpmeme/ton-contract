import "@stdlib/deploy";
import "@stdlib/ownable";
import "./jetton";
import "./jetton_messages";

contract Token with Jetton, Deployable, Ownable {
   
    total_supply: Int as coins;
    owner: Address;
    content: Cell;
    mintable: Bool;
    max_supply: Int as coins;
  
    init(_owner: Address,
        _content: Cell,
        _max_supply: Int) {
       
        self.total_supply = 0;
        self.owner = _owner;
        self.mintable = true;
        self.content = _content;
        self.max_supply = _max_supply;
        
    }

    receive(msg: MintAll){
        // methodId: 0x1767e827
        self.requireOwner();
        require(self.mintable, "Not mintable");
        self.mint(msg.receiver, self.max_supply, null);
        // self.mint(msg.receiver, self.max_supply, self.tokenLauncher); // (to, amount, response_destination)
        self.mintable = false;
        self.owner = address("0:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"); // set the _owner as the zero address

        // send(SendParameters{
        //         to: self.tokenLauncher,
        //         body: beginCell().endCell(),
        //         value: 0,
        //         mode: SendRemainingValue | SendIgnoreErrors
        //     }
        // );
        // self.reply(beginCell().endCell());
    }

    receive(msg: MintByPump) {
        self.requireOwner();
        require(self.mintable, "Not mintable");
        let ownerAmount: Int = self.max_supply - msg.receiverAmount;
        self.pumpMint(msg.owner,ownerAmount,msg.receiver,msg.receiverAmount,null);
        self.mintable = false;
        self.owner = address("0:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"); // set the _owner as the zero address
    }

    
    // get fun _tokenLauncher(): Address {
    //     return self.tokenLauncher;
    // }

    // get fun content(): Cell {
    //     return self.content;
    // }

    // get fun socialLinks(): String {
    //     let sb: StringBuilder = beginString();
    //     sb.append(self.website);
    //     sb.append("***");
    //     sb.append(self.telegram);
    //     sb.append("***");
    //     sb.append(self.twitter);
    //     return sb.toString();
    // }
}