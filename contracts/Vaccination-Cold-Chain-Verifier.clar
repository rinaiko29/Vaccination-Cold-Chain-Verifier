(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INVALID-TEMP (err u402))
(define-constant ERR-SHIPMENT-NOT-FOUND (err u404))
(define-constant ERR-ALREADY-RELEASED (err u405))
(define-constant ERR-ORACLE-NOT-AUTHORIZED (err u406))
(define-constant ERR-SHIPMENT-EXPIRED (err u407))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u408))

(define-constant MIN-TEMP 2)
(define-constant MAX-TEMP 8)
(define-constant SHIPMENT-DURATION u1440)

(define-constant ERR-NOT-INSURED (err u409))
(define-constant ERR-ALREADY-INSURED (err u410))
(define-constant ERR-INVALID-PREMIUM (err u411))

(define-constant BASIC-PREMIUM-RATE u10)
(define-constant PREMIUM-PREMIUM-RATE u20)
(define-constant BASIC-COVERAGE-PERCENT u30)
(define-constant PREMIUM-COVERAGE-PERCENT u60)

(define-data-var insurance-pool-balance uint u0)

(define-data-var next-shipment-id uint u1)
(define-data-var oracle-fee uint u1000)

(define-map authorized-oracles principal bool)
(define-map shipments uint {
    shipper: principal,
    receiver: principal,
    payment-amount: uint,
    start-block: uint,
    end-block: uint,
    is-completed: bool,
    is-payment-released: bool,
    temperature-violations: uint
})

(define-map temperature-logs uint (list 100 {
    timestamp: uint,
    temperature: int,
    oracle: principal
}))

(define-map shipment-status uint {
    current-temp: int,
    last-update: uint,
    violation-count: uint
})

(define-private (is-authorized-oracle (oracle principal))
    (default-to false (map-get? authorized-oracles oracle))
)

(define-private (is-valid-temperature (temp int))
    (and (>= temp MIN-TEMP) (<= temp MAX-TEMP))
)

(define-private (calculate-payment-release (violations uint) (payment uint))
    (if (is-eq violations u0)
        payment
        (if (<= violations u3)
            (/ (* payment u80) u100)
            (if (<= violations u6)
                (/ (* payment u50) u100)
                u0
            )
        )
    )
)

(define-public (add-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set authorized-oracles oracle true)
        (ok true)
    )
)

(define-public (remove-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-delete authorized-oracles oracle)
        (ok true)
    )
)

(define-public (create-shipment (receiver principal))
    (let (
        (shipment-id (var-get next-shipment-id))
        (payment (stx-get-balance tx-sender))
        (start-block stacks-block-height)
        (end-block (+ stacks-block-height SHIPMENT-DURATION))
    )
        (asserts! (> payment u0) ERR-INSUFFICIENT-PAYMENT)
        (try! (stx-transfer? payment tx-sender (as-contract tx-sender)))
        (map-set shipments shipment-id {
            shipper: tx-sender,
            receiver: receiver,
            payment-amount: payment,
            start-block: start-block,
            end-block: end-block,
            is-completed: false,
            is-payment-released: false,
            temperature-violations: u0
        })
        (map-set shipment-status shipment-id {
            current-temp: 5,
            last-update: start-block,
            violation-count: u0
        })
        (var-set next-shipment-id (+ shipment-id u1))
        (ok shipment-id)
    )
)

(define-public (record-temperature (shipment-id uint) (temperature int))
    (let (
        (shipment (unwrap! (map-get? shipments shipment-id) ERR-SHIPMENT-NOT-FOUND))
        (current-status (unwrap! (map-get? shipment-status shipment-id) ERR-SHIPMENT-NOT-FOUND))
        (current-logs (default-to (list) (map-get? temperature-logs shipment-id)))
        (is-valid-temp (is-valid-temperature temperature))
        (new-violations (if is-valid-temp 
            (get temperature-violations shipment) 
            (+ (get temperature-violations shipment) u1)))
    )
        (asserts! (is-authorized-oracle tx-sender) ERR-ORACLE-NOT-AUTHORIZED)
        (asserts! (not (get is-completed shipment)) ERR-ALREADY-RELEASED)
        (asserts! (<= stacks-block-height (get end-block shipment)) ERR-SHIPMENT-EXPIRED)
        
        (map-set temperature-logs shipment-id 
            (unwrap! (as-max-len? 
                (append current-logs {
                    timestamp: stacks-block-height,
                    temperature: temperature,
                    oracle: tx-sender
                }) u100) ERR-INVALID-TEMP))
        
        (map-set shipments shipment-id (merge shipment {
            temperature-violations: new-violations
        }))
        
        (map-set shipment-status shipment-id {
            current-temp: temperature,
            last-update: stacks-block-height,
            violation-count: new-violations
        })
        
        (ok true)
    )
)

(define-public (complete-shipment (shipment-id uint))
    (let (
        (shipment (unwrap! (map-get? shipments shipment-id) ERR-SHIPMENT-NOT-FOUND))
        (violations (get temperature-violations shipment))
        (payment-amount (get payment-amount shipment))
        (release-amount (calculate-payment-release violations payment-amount))
        (penalty-amount (- payment-amount release-amount))
    )
        (asserts! (is-eq tx-sender (get receiver shipment)) ERR-UNAUTHORIZED)
        (asserts! (not (get is-payment-released shipment)) ERR-ALREADY-RELEASED)
        
        (if (> release-amount u0)
            (try! (as-contract (stx-transfer? release-amount tx-sender (get shipper shipment))))
            true
        )
        
        (if (> penalty-amount u0)
            (try! (as-contract (stx-transfer? penalty-amount tx-sender CONTRACT-OWNER)))
            true
        )
        
        (map-set shipments shipment-id (merge shipment {
            is-completed: true,
            is-payment-released: true
        }))
        
        (ok release-amount)
    )
)

(define-public (emergency-complete (shipment-id uint))
    (let (
        (shipment (unwrap! (map-get? shipments shipment-id) ERR-SHIPMENT-NOT-FOUND))
    )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (asserts! (> stacks-block-height (get end-block shipment)) ERR-SHIPMENT-EXPIRED)
        (asserts! (not (get is-payment-released shipment)) ERR-ALREADY-RELEASED)
        
        (try! (as-contract (stx-transfer? (get payment-amount shipment) tx-sender (get shipper shipment))))
        
        (map-set shipments shipment-id (merge shipment {
            is-completed: true,
            is-payment-released: true
        }))
        
        (ok true)
    )
)

(define-read-only (get-shipment (shipment-id uint))
    (map-get? shipments shipment-id)
)

(define-read-only (get-temperature-logs (shipment-id uint))
    (map-get? temperature-logs shipment-id)
)

(define-read-only (get-shipment-status (shipment-id uint))
    (map-get? shipment-status shipment-id)
)

(define-read-only (is-oracle-authorized (oracle principal))
    (is-authorized-oracle oracle)
)

(define-read-only (get-next-shipment-id)
    (var-get next-shipment-id)
)

(define-map shipment-insurance uint {
    is-insured: bool,
    premium-paid: uint,
    coverage-tier: (string-ascii 10),
    max-refund: uint
})

(define-private (calculate-insurance-premium (payment uint) (tier (string-ascii 10)))
    (if (is-eq tier "basic")
        (/ (* payment BASIC-PREMIUM-RATE) u100)
        (if (is-eq tier "premium")
            (/ (* payment PREMIUM-PREMIUM-RATE) u100)
            u0
        )
    )
)

(define-private (calculate-coverage-amount (payment uint) (tier (string-ascii 10)))
    (if (is-eq tier "basic")
        (/ (* payment BASIC-COVERAGE-PERCENT) u100)
        (if (is-eq tier "premium")
            (/ (* payment PREMIUM-COVERAGE-PERCENT) u100)
            u0
        )
    )
)

(define-public (purchase-insurance (shipment-id uint) (tier (string-ascii 10)))
    (let (
        (shipment (unwrap! (map-get? shipments shipment-id) ERR-SHIPMENT-NOT-FOUND))
        (existing-insurance (map-get? shipment-insurance shipment-id))
        (premium (calculate-insurance-premium (get payment-amount shipment) tier))
        (coverage (calculate-coverage-amount (get payment-amount shipment) tier))
    )
        (asserts! (is-eq tx-sender (get shipper shipment)) ERR-UNAUTHORIZED)
        (asserts! (is-none existing-insurance) ERR-ALREADY-INSURED)
        (asserts! (> premium u0) ERR-INVALID-PREMIUM)
        (asserts! (or (is-eq tier "basic") (is-eq tier "premium")) ERR-INVALID-PREMIUM)
        
        (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
        
        (var-set insurance-pool-balance (+ (var-get insurance-pool-balance) premium))
        
        (map-set shipment-insurance shipment-id {
            is-insured: true,
            premium-paid: premium,
            coverage-tier: tier,
            max-refund: coverage
        })
        
        (ok coverage)
    )
)

(define-public (claim-insurance (shipment-id uint))
    (let (
        (shipment (unwrap! (map-get? shipments shipment-id) ERR-SHIPMENT-NOT-FOUND))
        (insurance (unwrap! (map-get? shipment-insurance shipment-id) ERR-NOT-INSURED))
        (violations (get temperature-violations shipment))
        (pool-balance (var-get insurance-pool-balance))
        (refund-amount (get max-refund insurance))
    )
        (asserts! (is-eq tx-sender (get shipper shipment)) ERR-UNAUTHORIZED)
        (asserts! (get is-completed shipment) ERR-SHIPMENT-NOT-FOUND)
        (asserts! (> violations u6) ERR-UNAUTHORIZED)
        (asserts! (>= pool-balance refund-amount) ERR-INSUFFICIENT-PAYMENT)
        
        (try! (as-contract (stx-transfer? refund-amount tx-sender (get shipper shipment))))
        
        (var-set insurance-pool-balance (- pool-balance refund-amount))
        
        (ok refund-amount)
    )
)

(define-read-only (get-insurance-details (shipment-id uint))
    (map-get? shipment-insurance shipment-id)
)

(define-read-only (get-pool-balance)
    (ok (var-get insurance-pool-balance))
)