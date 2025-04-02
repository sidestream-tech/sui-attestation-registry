# Sui Attestation Registry PoC

A monorepo containing:

- [attestation](./attestation/) – Sui/Move package that implements Sui Attestation Registry [SIP draft](https://github.com/sui-foundation/sips/pull/56)
- [attestation_type_example](./attestation_type_example/) – Sui/Move package that implement example type by integrating `attestation` package
- `attestation_tslib` – Typescript library that implements common functions to interact with attestations
- `attestation_frontend` – PoC implementation of the UI over the package using `attestation_tslib` library
