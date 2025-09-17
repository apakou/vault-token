#[starknet::interface]
trait IsBTC<TContractState> {
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, account: ContractAddress, amount: u256);
}

#[starknet::contract]
mod sBTC {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::ERC20Component;
    use starknet::ContractAddress;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;

    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        initial_supply: u256,
        recipient: ContractAddress,
        owner: ContractAddress
    ) {
        // Initialiser l'ERC20 avec les métadonnées
        self.erc20.initializer("Simulated Bitcoin", "sBTC");
        
        // Initialiser le système de propriété
        self.ownable.initializer(owner);
        
        // Mint l'approvisionnement initial au destinataire
        if initial_supply > 0 {
            self.erc20._mint(recipient, initial_supply);
        }
    }

    #[external(v0)]
    impl sBTCImpl of super::IsBTC<ContractState> {
        /// Mint des nouveaux tokens sBTC - réservé au propriétaire
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            self.erc20._mint(recipient, amount);
        }

        /// Burn des tokens sBTC - réservé au propriétaire
        fn burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            self.erc20._burn(account, amount);
        }
    }
}
