;; food-safety-core.clar
;; Main contract for Food Safety Verification and Recall System
;; This contract manages system configuration and provides central event logging

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-PARAMETER (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-DOES-NOT-EXIST (err u103))
(define-constant ERR-SAFETY-VIOLATION (err u104))
(define-constant ERR-CONTRACT-NOT-WHITELISTED (err u105))

;; Safety status enum values as constants
(define-constant STATUS-SAFE "safe")
(define-constant STATUS-PENDING "pending-verification")
(define-constant STATUS-FLAGGED "flagged")
(define-constant STATUS-RECALLED "recalled")

;; Data maps and variables
(define-data-var contract-owner principal tx-sender)
(define-data-var system-status (string-ascii 20) "operational")
(define-data-var system-version (string-ascii 10) "1.0.0")
(define-data-var event-counter uint u0)

;; Map of authorized contracts that can interact with this contract
(define-map authorized-contracts principal bool)

;; Map of system administrators
(define-map administrators principal bool)

;; Map of regulatory agencies with special access
(define-map regulatory-agencies
  { agency-id: (string-ascii 32) }
  {
    principal-address: principal,
    agency-name: (string-ascii 64),
    jurisdiction: (string-ascii 32),
    access-level: uint
  }
)

;; System events log
(define-map system-events
  { event-id: uint }
  {
    event-type: (string-ascii 32),
    event-data: (string-ascii 256),
    timestamp: uint,
    initiated-by: principal
  }
)

;; Global safety thresholds
(define-map safety-thresholds
  { parameter-id: (string-ascii 32) }
  {
    min-value: int,
    max-value: int,
    critical-threshold: int,
    unit: (string-ascii 16)
  }
)

;; ============
;; Authorization functions
;; ============

;; Check if caller is the contract owner
(define-private (is-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Check if caller is an administrator
(define-private (is-administrator)
  (default-to false (map-get? administrators tx-sender))
)

;; Check if caller is an authorized contract
(define-private (is-authorized-contract)
  (default-to false (map-get? authorized-contracts contract-caller))
)

;; Check if caller is a regulatory agency
(define-private (is-regulatory-agency)
  ;; In Clarity, we can't dynamically get all keys from a map
  ;; Since this is a limitation, we'll check if the caller is a regulatory agency
  ;; by directly querying the regulatory agencies map
  (match (map-get? regulatory-agencies-by-principal tx-sender)
    agency-id true
    false
  )
)

;; Map of regulatory agencies indexed by principal for faster lookups
(define-map regulatory-agencies-by-principal
  principal
  (string-ascii 32)
)

;; ============
;; Event logging without string concatenation
;; ============

;; Log a system event (private function used internally)
(define-private (log-event (event-type (string-ascii 32)) (event-data (string-ascii 256)))
  (let ((event-id (var-get event-counter)))
    (map-set system-events
      { event-id: event-id }
      {
        event-type: event-type,
        event-data: event-data,
        timestamp: block-height,
        initiated-by: tx-sender
      }
    )
    (var-set event-counter (+ event-id u1))
    event-id
  )
)

;; ============
;; Owner/admin management
;; ============

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-owner) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

;; Add administrator
(define-public (add-administrator (admin principal))
  (begin
    (asserts! (is-owner) ERR-NOT-AUTHORIZED)
    (map-set administrators admin true)
    (ok true)
  )
)

;; Remove administrator
(define-public (remove-administrator (admin principal))
  (begin
    (asserts! (is-owner) ERR-NOT-AUTHORIZED)
    (map-delete administrators admin)
    (ok true)
  )
)

;; Whitelist a contract to interact with this contract
(define-public (whitelist-contract (contract-principal principal))
  (begin
    (asserts! (or (is-owner) (is-administrator)) ERR-NOT-AUTHORIZED)
    (map-set authorized-contracts contract-principal true)
    (ok true)
  )
)

;; Remove a contract from whitelist
(define-public (remove-contract-whitelist (contract-principal principal))
  (begin
    (asserts! (or (is-owner) (is-administrator)) ERR-NOT-AUTHORIZED)
    (map-delete authorized-contracts contract-principal)
    (ok true)
  )
)

;; ============
;; System status management
;; ============

;; Update system status
(define-public (update-system-status (new-status (string-ascii 20)))
  (begin
    (asserts! (or (is-owner) (is-administrator)) ERR-NOT-AUTHORIZED)
    (var-set system-status new-status)
    (log-event "status-change" new-status)
    (ok true)
  )
)

;; Get current system status (read-only function)
(define-read-only (get-system-status)
  (var-get system-status)
)

;; Update system version
(define-public (update-system-version (new-version (string-ascii 10)))
  (begin
    (asserts! (is-owner) ERR-NOT-AUTHORIZED)
    (var-set system-version new-version)
    (log-event "version-update" new-version)
    (ok true)
  )
)

;; Get current system version (read-only function)
(define-read-only (get-system-version)
  (var-get system-version)
)

;; ============
;; Regulatory agency management
;; ============

;; Register a regulatory agency
(define-public (register-regulatory-agency 
  (agency-id (string-ascii 32)) 
  (agency-principal principal) 
  (agency-name (string-ascii 64)) 
  (jurisdiction (string-ascii 32)) 
  (access-level uint)
)
  (begin
    (asserts! (or (is-owner) (is-administrator)) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? regulatory-agencies { agency-id: agency-id })) ERR-ALREADY-EXISTS)
    
    (map-set regulatory-agencies
      { agency-id: agency-id }
      {
        principal-address: agency-principal,
        agency-name: agency-name,
        jurisdiction: jurisdiction,
        access-level: access-level
      }
    )
    
    ;; Also index by principal for faster lookups
    (map-set regulatory-agencies-by-principal agency-principal agency-id)
    
    (log-event "agency-registered" agency-id)
    (ok true)
  )
)

;; Update a regulatory agency
(define-public (update-regulatory-agency 
  (agency-id (string-ascii 32)) 
  (agency-principal principal) 
  (agency-name (string-ascii 64)) 
  (jurisdiction (string-ascii 32)) 
  (access-level uint)
)
  (begin
    (asserts! (or (is-owner) (is-administrator)) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? regulatory-agencies { agency-id: agency-id })) ERR-DOES-NOT-EXIST)
    
    ;; Get old record to update the principal index if needed
    (let ((old-record (unwrap-panic (map-get? regulatory-agencies { agency-id: agency-id }))))
      ;; If principal changed, update the index
      (if (not (is-eq (get principal-address old-record) agency-principal))
        (begin
          ;; Remove old principal mapping
          (map-delete regulatory-agencies-by-principal (get principal-address old-record))
          ;; Add new principal mapping
          (map-set regulatory-agencies-by-principal agency-principal agency-id)
        )
        ;; If principal didn't change, do nothing
        true
      )
    )
    
    (map-set regulatory-agencies
      { agency-id: agency-id }
      {
        principal-address: agency-principal,
        agency-name: agency-name,
        jurisdiction: jurisdiction,
        access-level: access-level
      }
    )
    
    (log-event "agency-updated" agency-id)
    (ok true)
  )
)

;; Remove a regulatory agency
(define-public (remove-regulatory-agency (agency-id (string-ascii 32)))
  (begin
    (asserts! (or (is-owner) (is-administrator)) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? regulatory-agencies { agency-id: agency-id })) ERR-DOES-NOT-EXIST)
    
    ;; Get the principal to remove it from the index
    (let ((agency (unwrap-panic (map-get? regulatory-agencies { agency-id: agency-id }))))
      ;; Remove from principal index
      (map-delete regulatory-agencies-by-principal (get principal-address agency))
    )
    
    ;; Remove from main map
    (map-delete regulatory-agencies { agency-id: agency-id })
    (log-event "agency-removed" agency-id)
    (ok true)
  )
)

;; ============
;; Safety threshold management
;; ============

;; Set safety threshold for a parameter
(define-public (set-safety-threshold 
  (parameter-id (string-ascii 32)) 
  (min-value int) 
  (max-value int) 
  (critical-threshold int) 
  (unit (string-ascii 16))
)
  (begin
    (asserts! (or (is-owner) (is-administrator) (is-regulatory-agency)) ERR-NOT-AUTHORIZED)
    
    (map-set safety-thresholds
      { parameter-id: parameter-id }
      {
        min-value: min-value,
        max-value: max-value,
        critical-threshold: critical-threshold,
        unit: unit
      }
    )
    
    (log-event "threshold-set" parameter-id)
    (ok true)
  )
)

;; Get safety threshold for a parameter (read-only function)
(define-read-only (get-safety-threshold (parameter-id (string-ascii 32)))
  (map-get? safety-thresholds { parameter-id: parameter-id })
)

;; Check if a value is within safety threshold
(define-read-only (is-within-threshold (parameter-id (string-ascii 32)) (value int))
  (let ((threshold (map-get? safety-thresholds { parameter-id: parameter-id })))
    (if (is-some threshold)
      (let ((threshold-value (unwrap-panic threshold)))
        (and 
          (>= value (get min-value threshold-value)) 
          (<= value (get max-value threshold-value))
        )
      )
      false
    )
  )
)

;; Check if a value exceeds critical threshold
(define-read-only (is-critical-violation (parameter-id (string-ascii 32)) (value int))
  (let ((threshold (map-get? safety-thresholds { parameter-id: parameter-id })))
    (if (is-some threshold)
      (let ((threshold-value (unwrap-panic threshold)))
        (>= value (get critical-threshold threshold-value))
      )
      false
    )
  )
)

;; Public function to log a system event (can only be called by authorized contracts)
(define-public (record-system-event (event-type (string-ascii 32)) (event-data (string-ascii 256)))
  (begin
    (asserts! (or (is-owner) (is-administrator) (is-authorized-contract)) ERR-NOT-AUTHORIZED)
    (ok (log-event event-type event-data))
  )
)

;; Get an event by ID (read-only function)
(define-read-only (get-event-by-id (event-id uint))
  (map-get? system-events { event-id: event-id })
)

;; Initialize contract
;; Add contract owner as the first administrator
(map-set administrators tx-sender true)