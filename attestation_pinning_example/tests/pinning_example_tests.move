#[test_only]
module attestation_pinning_example::pinning_example_tests;

/// Imports
use std::ascii;
use sui::test_scenario;
use sui::package::{Publisher};
use attestation::attestation::{Self, Registry, AttestationType};
use attestation_type_example::type_example::{Self, ExampleAttestation};
use attestation_pinning_example::pinning_example::{Self};

#[test]
fun test_happy_path() {
    let registry_creator = @0xA11CE;
    let type_creator = @0xB0B;
    let attestation_creator = @0xCAFE;
    let receiver_creator = @0xFACE;
    let attestation_receiver = @attestation_pinning_example;

    let mut scenario = test_scenario::begin(registry_creator);
    // Publish attestation package
    {
        attestation::test_init(test_scenario::ctx(&mut scenario));
    };

    scenario.next_tx(type_creator);
    // Publish type package
    {
        type_example::test_init(test_scenario::ctx(&mut scenario));
    };

    scenario.next_tx(type_creator);
    // Register itself
    {
        // Borrow required objects
        let type_publisher = test_scenario::take_from_address<Publisher>(&scenario, type_creator);
        let mut package_registry = test_scenario::take_shared<Registry>(&scenario);

        type_example::register_itself(type_publisher, &mut package_registry, test_scenario::ctx(&mut scenario));

        test_scenario::return_shared(package_registry);
    };

    scenario.next_tx(receiver_creator);
    // Publish package to be attested
    {
        pinning_example::test_init(test_scenario::ctx(&mut scenario));
    };

    scenario.next_tx(attestation_creator);
    // Attest
    {
        // Borrow required objects
        let mut package_registry = test_scenario::take_shared<Registry>(&scenario);
        let attestation_type = test_scenario::take_immutable<AttestationType<ExampleAttestation>>(&scenario);

        // Try to create attestation
        let revoke_cap = type_example::attest(
            attestation_receiver,
            ascii::string(b"test"),
            &attestation_type,
            &mut package_registry,
            test_scenario::ctx(&mut scenario),
        );
        transfer::public_transfer(revoke_cap, attestation_creator);

        // Return borrowed
        test_scenario::return_shared(package_registry);
        test_scenario::return_immutable(attestation_type);
    };

    scenario.next_tx(receiver_creator);
    // Pin/unpin attestation
    {
        // Borrow required objects
        let mut package_registry = test_scenario::take_shared<Registry>(&scenario);
        let mut receiver_publisher = test_scenario::take_from_address<Publisher>(&scenario, receiver_creator);

        attestation::pin<ExampleAttestation>(
            &mut receiver_publisher,
            attestation_receiver,
            attestation_creator,
            &mut package_registry,
        );
        attestation::unpin<ExampleAttestation>(
            &mut receiver_publisher,
            attestation_receiver,
            attestation_creator,
            &mut package_registry,
        );

        test_scenario::return_shared(package_registry);
        test_scenario::return_to_address(receiver_creator, receiver_publisher);
    };

    scenario.end();
}
