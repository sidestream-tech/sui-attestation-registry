#[test_only]
module attestation::attestation_tests;

/// Imports
use sui::test_scenario;
use sui::package::{Self, Publisher};
use attestation::attestation::{Self, Registry, AttestationType, RevokeCap};

/// Test attestation type
public struct TestAttestation has key, store {
    id: UID,
    is_good: bool,
}

/// OTW to claim publisher
public struct ATTESTATION_TESTS has drop {}

/// Initilise the module by claiming publisher object
fun init(otw: ATTESTATION_TESTS, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);
    transfer::public_transfer(publisher, ctx.sender());
}

#[test]
fun test_happy_path() {
    let registry_creator = @0xA11CE;
    let type_creator = @0xB0B;
    let attestation_creator = @0xCAFE;
    let attestation_receiver = @0xFACE;

    let mut scenario = test_scenario::begin(registry_creator);
    // Publish attestation package
    {
        attestation::test_init(test_scenario::ctx(&mut scenario));
    };

    scenario.next_tx(type_creator);
    // Publish type package
    {
        init(ATTESTATION_TESTS {}, test_scenario::ctx(&mut scenario));
    };

    scenario.next_tx(attestation_creator);
    // Register new type
    {
        // Borrow required objects
        let mut package_registry = test_scenario::take_shared<Registry>(&scenario);
        let type_publisher = test_scenario::take_from_address<Publisher>(&scenario, type_creator);

        // Try to create type
        attestation::register_type<TestAttestation>(
            type_publisher,
            vector[],
            vector[],
            &mut package_registry,
            test_scenario::ctx(&mut scenario)
        );

        // Return borrowed
        test_scenario::return_shared(package_registry);
    };

    scenario.next_tx(attestation_creator);
    // Create new attestation
    {
        // Borrow required objects
        let mut package_registry = test_scenario::take_shared<Registry>(&scenario);
        let attestation_type = test_scenario::take_immutable<AttestationType<TestAttestation>>(&scenario);
        
        let revoke_cap = attestation::attest<TestAttestation>(
            TestAttestation {
                id: object::new(test_scenario::ctx(&mut scenario)),
                is_good: true
            },
            attestation_receiver,
            &attestation_type,
            &mut package_registry,
            test_scenario::ctx(&mut scenario),
        );

        // Return borrowed
        transfer::public_transfer(revoke_cap, attestation_creator);
        test_scenario::return_immutable(attestation_type);
        test_scenario::return_shared(package_registry);
    };

    scenario.next_tx(attestation_creator);
    // Revoke previously created attestation
    {
        // Borrow required objects
        let revoke_cap = test_scenario::take_from_address<RevokeCap>(&scenario, attestation_creator);
        let mut package_registry = test_scenario::take_shared<Registry>(&scenario);

        // Sanity check
        assert!(attestation::get_attestation_revoked_by<TestAttestation>(attestation_receiver, attestation_creator, &package_registry) == option::none());

        // Revoke
        attestation::revoke<TestAttestation>(
            revoke_cap,
            &mut package_registry,
            test_scenario::ctx(&mut scenario),
        );
        assert!(attestation::get_attestation_revoked_by<TestAttestation>(attestation_receiver, attestation_creator, &package_registry) == option::some(attestation_creator));

        // Return borrowed
        test_scenario::return_shared(package_registry);
    };

    scenario.end();
}
