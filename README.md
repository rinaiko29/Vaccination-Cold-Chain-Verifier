# 💉 Vaccination Cold-Chain Verifier

## 🌡️ Overview

A Clarity smart contract that ensures vaccine temperature integrity during transport using IoT sensors and oracle-based verification. Payments are released based on temperature compliance, creating accountability in the cold-chain delivery process.

## 🚀 Features

- ❄️ **Temperature Monitoring**: Continuous logging via authorized oracles
- 💰 **Escrow Payments**: Automatic fund release based on compliance
- 🎯 **Violation Tracking**: Temperature breach counting and penalties  
- ⚡ **Emergency Controls**: Manual override for expired shipments
- 📊 **Real-time Status**: Query shipment and temperature data

## 🔧 Usage

### Deploy Contract

```bash
clarinet deploy
```

### Add Oracle 🔮

```clarity
(contract-call? .Vaccination-Cold-Chain-Verifier add-oracle 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

### Create Shipment 📦

```clarity
(contract-call? .Vaccination-Cold-Chain-Verifier create-shipment 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

### Record Temperature 🌡️

```clarity
(contract-call? .Vaccination-Cold-Chain-Verifier record-temperature u1 5)
```

### Complete Shipment ✅

```clarity
(contract-call? .Vaccination-Cold-Chain-Verifier complete-shipment u1)
```

## 📋 Temperature Rules

| Range | Status | Payment Release |
|-------|--------|----------------|
| 2-8°C | ✅ Valid | 100% |
| Outside range | ❌ Violation | Penalty applied |

## 💸 Payment Structure

- **0 violations**: 100% payment release
- **1-3 violations**: 80% payment release  
- **4-6 violations**: 50% payment release
- **7+ violations**: 0% payment release

## 🔍 Read Functions

```clarity
(get-shipment u1)
(get-temperature-logs u1)  
(get-shipment-status u1)
(is-oracle-authorized 'SP...)
```

## ⏱️ Parameters

- **Temperature Range**: 2°C to 8°C
- **Shipment Duration**: 1440 blocks (~10 days)
- **Max Temperature Logs**: 100 per shipment

## 🛡️ Security

- Owner-only oracle management
- Authorized oracle validation
- Automatic penalty distribution
- Emergency completion controls

## 🏗️ Development

Run tests:
```bash
clarinet test
```

Check syntax:
```bash  
clarinet check
```

## 📄 License

MIT License - Build responsibly! 🌍
