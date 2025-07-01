module attestation_type_example::type_example;

use sui::package::{Self, Publisher};
use std::ascii::{String};
use attestation::attestation::{Self, Registry, AttestationType, RevokeCap};

/// Attestation type
public struct ExampleAttestation has key, store {
    id: UID,
    what: String,
}

/// OTW to claim publisher
public struct TYPE_EXAMPLE has drop {}

/// Initilise the module by claiming publisher object
fun init(otw: TYPE_EXAMPLE, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);
    transfer::public_transfer(publisher, ctx.sender());
}

/// Create attestation type and its Display
public fun register_itself(
    publisher: Publisher,
    registry: &mut Registry,
    ctx: &mut TxContext,
) {
    let fields = vector[
        b"name".to_string(),
        b"description".to_string(),
        b"link".to_string(),
    ];
    let values = vector[
        b"Attestation Type Example".to_string(),
        b"Test usage of the Attesation package".to_string(),
        b"https://example.com/attestation/{id}".to_string(),
    ];
    attestation::register_type<ExampleAttestation>(
        publisher,
        fields,
        values,
        registry,
        ctx,
    )
}

/// Create attestation
public fun attest(
    receiver: address,
    what: String,
    attestation_type: &AttestationType<ExampleAttestation>,
    registry: &mut Registry,
    ctx: &mut TxContext,
): RevokeCap {
    let attestation_data = ExampleAttestation {
        id: object::new(ctx),
        what,
    };
    attestation::attest<ExampleAttestation>(
        attestation_data,
        receiver,
        attestation_type,
        registry,
        ctx,
    )
}

#[test_only]
/// Wrapper of module initializer for testing
public fun test_init(ctx: &mut TxContext) {
    init(TYPE_EXAMPLE {}, ctx)
}
