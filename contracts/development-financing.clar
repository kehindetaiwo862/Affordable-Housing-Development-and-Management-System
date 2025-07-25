;; Development Financing Coordination Contract
;; Combines public and private funding for affordable housing projects

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-INPUT (err u201))
(define-constant ERR-PROJECT-NOT-FOUND (err u202))
(define-constant ERR-INSUFFICIENT-FUNDS (err u203))
(define-constant ERR-PROJECT-COMPLETED (err u204))
(define-constant ERR-INVALID-STATUS (err u205))

;; Data Variables
(define-data-var project-counter uint u0)
(define-data-var total-public-funds uint u0)
(define-data-var total-private-funds uint u0)

;; Data Maps
(define-map projects
  { project-id: uint }
  {
    name: (string-ascii 100),
    total-budget: uint,
    units-planned: uint,
    public-funding: uint,
    private-funding: uint,
    funds-disbursed: uint,
    status: (string-ascii 20),
    developer: principal,
    created-at: uint,
    completion-target: uint
  }
)

(define-map funding-sources
  { source-id: uint }
  {
    source-name: (string-ascii 50),
    source-type: (string-ascii 20),
    total-committed: uint,
    total-disbursed: uint,
    funder: principal
  }
)

(define-map project-milestones
  { project-id: uint, milestone-id: uint }
  {
    description: (string-ascii 100),
    target-date: uint,
    completion-date: (optional uint),
    funding-release: uint,
    completed: bool
  }
)

;; Private Functions
(define-private (is-valid-status (status (string-ascii 20)))
  (or (is-eq status "Planning")
      (or (is-eq status "Approved")
          (or (is-eq status "Construction")
              (or (is-eq status "Completed")
                  (is-eq status "Cancelled"))))))

;; Public Functions
(define-public (create-project
  (name (string-ascii 100))
  (total-budget uint)
  (units-planned uint)
  (completion-target uint))
  (let ((project-id (+ (var-get project-counter) u1)))
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> total-budget u0) ERR-INVALID-INPUT)
    (asserts! (> units-planned u0) ERR-INVALID-INPUT)
    (asserts! (> completion-target block-height) ERR-INVALID-INPUT)

    (map-set projects
      { project-id: project-id }
      {
        name: name,
        total-budget: total-budget,
        units-planned: units-planned,
        public-funding: u0,
        private-funding: u0,
        funds-disbursed: u0,
        status: "Planning",
        developer: tx-sender,
        created-at: block-height,
        completion-target: completion-target
      })

    (var-set project-counter project-id)
    (ok project-id)))

(define-public (add-funding
  (project-id uint)
  (amount uint)
  (funding-type (string-ascii 20)))
  (let ((project (unwrap! (map-get? projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND)))
    (asserts! (> amount u0) ERR-INVALID-INPUT)
    (asserts! (or (is-eq funding-type "Public") (is-eq funding-type "Private")) ERR-INVALID-INPUT)
    (asserts! (not (is-eq (get status project) "Completed")) ERR-PROJECT-COMPLETED)

    (if (is-eq funding-type "Public")
        (begin
          (map-set projects
            { project-id: project-id }
            (merge project { public-funding: (+ (get public-funding project) amount) }))
          (var-set total-public-funds (+ (var-get total-public-funds) amount)))
        (begin
          (map-set projects
            { project-id: project-id }
            (merge project { private-funding: (+ (get private-funding project) amount) }))
          (var-set total-private-funds (+ (var-get total-private-funds) amount))))

    (ok true)))

(define-public (disburse-funds
  (project-id uint)
  (amount uint))
  (let ((project (unwrap! (map-get? projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
        (total-funding (+ (get public-funding project) (get private-funding project))))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-INPUT)
    (asserts! (<= (+ (get funds-disbursed project) amount) total-funding) ERR-INSUFFICIENT-FUNDS)

    (map-set projects
      { project-id: project-id }
      (merge project { funds-disbursed: (+ (get funds-disbursed project) amount) }))

    (ok true)))

(define-public (update-project-status
  (project-id uint)
  (new-status (string-ascii 20)))
  (let ((project (unwrap! (map-get? projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get developer project)) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-status new-status) ERR-INVALID-STATUS)

    (map-set projects
      { project-id: project-id }
      (merge project { status: new-status }))

    (ok true)))

(define-public (add-milestone
  (project-id uint)
  (milestone-id uint)
  (description (string-ascii 100))
  (target-date uint)
  (funding-release uint))
  (let ((project (unwrap! (map-get? projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get developer project)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len description) u0) ERR-INVALID-INPUT)
    (asserts! (> target-date block-height) ERR-INVALID-INPUT)

    (map-set project-milestones
      { project-id: project-id, milestone-id: milestone-id }
      {
        description: description,
        target-date: target-date,
        completion-date: none,
        funding-release: funding-release,
        completed: false
      })

    (ok true)))

;; Read-only Functions
(define-read-only (get-project (project-id uint))
  (map-get? projects { project-id: project-id }))

(define-read-only (get-project-funding-status (project-id uint))
  (match (map-get? projects { project-id: project-id })
    project (let ((total-funding (+ (get public-funding project) (get private-funding project)))
                  (funding-gap (if (> (get total-budget project) total-funding)
                                  (- (get total-budget project) total-funding)
                                  u0)))
              (ok {
                total-budget: (get total-budget project),
                total-funding: total-funding,
                funding-gap: funding-gap,
                percent-funded: (if (> (get total-budget project) u0)
                                   (/ (* total-funding u100) (get total-budget project))
                                   u0)
              }))
    ERR-PROJECT-NOT-FOUND))

(define-read-only (get-milestone (project-id uint) (milestone-id uint))
  (map-get? project-milestones { project-id: project-id, milestone-id: milestone-id }))

(define-read-only (get-total-projects)
  (var-get project-counter))

(define-read-only (get-funding-summary)
  {
    total-public-funds: (var-get total-public-funds),
    total-private-funds: (var-get total-private-funds),
    total-funds: (+ (var-get total-public-funds) (var-get total-private-funds))
  })
