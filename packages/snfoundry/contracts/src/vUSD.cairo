#[starknet::interface]
trait IvUSD<TContractState> {
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn burn(ref self: TContractState, account: ContractAddress, amount: u256);
    fn get_minter(self: @TContractState) -> ContractAddress;
    fn set_minter(ref self: TContractState, new_minter: ContractAddress);
}

#[starknet::contract]
mod vUSD {
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::ERC20Component;
    use starknet::ContractAddress;
    use starknet::get_caller_address;

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
        // Adresse autorisée à minter des vUSD
        minter: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        MinterChanged: MinterChanged,
    }

    #[derive(Drop, starknet::Event)]
    struct MinterChanged {
        #[key]
        old_minter: ContractAddress,
        #[key]
        new_minter: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        minter: ContractAddress
    ) {
        // Initialiser l'ERC20 avec les métadonnées du stablecoin
        self.erc20.initializer("Volta USD", "vUSD");
        
        // Initialiser le système de propriété
        self.ownable.initializer(owner);
        
        // Définir l'adresse autorisée à minter
        self.minter.write(minter);
    }

    #[external(v0)]
    impl vUSDImpl of super::IvUSD<ContractState> {
        /// Mint des nouveaux tokens vUSD - réservé au minter autorisé
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            self._assert_only_minter();
            self.erc20._mint(recipient, amount);
        }

        /// Burn des tokens vUSD - réservé au minter autorisé
        fn burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            self._assert_only_minter();
            self.erc20._burn(account, amount);
        }

        /// Récupérer l'adresse du minter autorisé
        fn get_minter(self: @ContractState) -> ContractAddress {
            self.minter.read()
        }

        /// Changer l'adresse du minter - réservé au propriétaire
        fn set_minter(ref self: ContractState, new_minter: ContractAddress) {
            self.ownable.assert_only_owner();
            let old_minter = self.minter.read();
            self.minter.write(new_minter);
            
            self.emit(MinterChanged { old_minter, new_minter });
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Fonction interne pour vérifier que seul le minter peut appeler certaines fonctions
        fn _assert_only_minter(self: @ContractState) {
            let caller = get_caller_address();
            let authorized_minter = self.minter.read();
            assert(caller == authorized_minter, 'Only minter can call this');
        }
    }
}
