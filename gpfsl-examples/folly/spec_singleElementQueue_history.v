From gpfsl.examples Require Import sflib.

From stdpp Require Import namespaces.

From gpfsl.logic Require Import logatom.

From gpfsl.examples.omo Require Export omo omo_preds append_only_loc.

Require Import iris.prelude.options.

Local Open Scope Z_scope.

Inductive seq_event := Init | Enq (v : Z) (n : nat) | Deq (v : Z) (n : nat).
Definition seq_state := list (event_id * Z * nat* view * eView).
Global Instance seq_event_inhabited : Inhabited seq_event := populate Init.

Local Notation history := (history seq_event).
Local Notation empty := 0 (only parsing).
Implicit Types (E : history) (st : seq_state).

Inductive seq_step : ∀ (e : event_id) (eV : omo_event seq_event) st st', Prop :=
  | seq_step_Enq e eV v n
    (ENQ : eV.(type) = Enq v n)
    (GT : 0 < v)
    (EVIEW : e ∈ eV.(eview))
    : seq_step e eV [] [(e, v, n, eV.(sync), eV.(eview))]
  | seq_step_Deq e eV e' v n V lV
    (DEQ : eV.(type) = Deq v n)
    (GT : 0 < v)
    (SYNC : V ⊑ eV.(sync))
    (EVIEW : {[e; e']} ∪ lV ⊆ eV.(eview))
    : seq_step e eV [(e', v, n, V, lV)] []
  | seq_step_Init eV
    (INIT : eV.(type) = Init)
    (EVIEW : eV.(eview) = {[0%nat]})
    : seq_step 0%nat eV [] []
  .

Global Instance seq_interpretable : Interpretable seq_event seq_state :=
  {
    init := [];
    step := seq_step
  }.

Inductive seq_perm_type := EnqP | DeqP.
Global Instance seq_perm_type_inhabited : Inhabited seq_perm_type := populate EnqP.

Definition SeqLocalT Σ : Type :=
  ∀ (γg : gname) (q : loc) (E : history) (M : eView), vProp Σ.
Definition SeqLocalNT Σ : Type :=
  ∀ (N : namespace), SeqLocalT Σ.
Definition SeqInvT Σ : Type :=
  ∀ (γg : gname) (q : loc) (E : history), vProp Σ.
Definition SeqPermT Σ : Type :=
  ∀ (γg : gname) (q : loc) (ty : seq_perm_type) (P : nat → bool), vProp Σ.

Definition new_seq_spec' {Σ} `{!noprolG Σ}
  (newSEQ : val) (SeqLocal : SeqLocalNT Σ) (SeqInv : SeqInvT Σ) (SeqPerm : SeqPermT Σ) : Prop :=
  ∀ N tid V,
  {{{ ⊒V }}}
    newSEQ [] @ tid; ⊤
  {{{ γg (q: loc) E M V', RET #q;
      ⊒V' ∗ @{V'} SeqLocal N γg q E M ∗ SeqInv γg q E ∗ SeqPerm γg q EnqP (λ _, true) ∗ SeqPerm γg q DeqP (λ _, true) ∗
      ⌜ E = [mkOmoEvent Init V' M] ∧ V ⊑ V' ⌝ }}}.

Definition enqueueWithTicket_spec' {Σ} `{!noprolG Σ}
  (enqueueWithTicket : val) (SeqLocal : SeqLocalNT Σ) (SeqInv : SeqInvT Σ) (SeqPerm : SeqPermT Σ) : Prop :=
  ∀ N (DISJ: N ## histN) (q: loc) tid γg E1 M (V : view) (v : Z) (n : nat),
  (* PRIVATE PRE *)
  (* E1 is a snapshot of the history, locally observed by M *)
  0 < v →
  ⊒V -∗ SeqLocal N γg q E1 M -∗ SeqPerm γg q EnqP (λ m, m =? n)%nat -∗
  (* PUBLIC PRE *)
  <<< ∀ E, ▷ SeqInv γg q E >>>
    enqueueWithTicket [ #q; #n; #v] @ tid; ↑N
  <<< ∃ V' E' M',
      (* PUBLIC POST *)
      ▷ SeqInv γg q E' ∗
      ⊒V' ∗ @{V'} SeqLocal N γg q E' M' ∗
      ⌜ V ⊑ V' ∧
        E' = E ++ [mkOmoEvent (Enq v n) V' M'] ∧ M ⊆ M' ⌝,
      RET #☠, emp >>>
  .

Definition dequeueWithTicket_spec' {Σ} `{!noprolG Σ}
  (dequeueWithTicket : val) (SeqLocal : SeqLocalNT Σ) (SeqInv : SeqInvT Σ) (SeqPerm : SeqPermT Σ) : Prop :=
  ∀ N (DISJ: N ## histN) (q: loc) tid γg E1 M (V : view) (n : nat),
  (* PRIVATE PRE *)
  (* E1 is a snapshot of the history, locally observed by M *)
  ⊒V -∗ SeqLocal N γg q E1 M -∗ SeqPerm γg q DeqP (λ m, m =? n)%nat -∗
  (* PUBLIC PRE *)
  <<< ∀ E, ▷ SeqInv γg q E >>>
    dequeueWithTicket [ #q; #n] @ tid; ↑N
  <<< ∃ V' E' M' (v : Z),
      (* PUBLIC POST *)
      ▷ SeqInv γg q E' ∗
      ⊒V' ∗ @{V'} SeqLocal N γg q E' M' ∗
      ⌜ V ⊑ V' ∧
        E' = E ++ [mkOmoEvent (Deq v n) V' M'] ∧ M ⊆ M' ∧ 0 < v⌝,
      RET #v, emp >>>
  .

Record seq_spec {Σ} `{!noprolG Σ} := SeqSpec {
  (** operations *)
  newSEQ : val;
  enqueueWithTicket : val;
  dequeueWithTicket : val;

  (** These are common elements in arbitrary history-style spec *)
  (** predicates *)
  SeqLocal : SeqLocalNT Σ;
  SeqInv : SeqInvT Σ;
  SeqPerm : SeqPermT Σ;

  (** predicates properties *)
  SeqInv_Objective : ∀ γg q E, Objective (SeqInv γg q E);
  SeqInv_Linearizable : ∀ γg q E, SeqInv γg q E ⊢ ⌜ Linearizability E ⌝;
  SeqInv_history_wf :
    ∀ γg q E, SeqInv γg q E ⊢ ⌜ history_wf E ⌝;

  SeqInv_SeqLocal :
    ∀ N γg q E E' M',
      SeqInv γg q E -∗ SeqLocal N γg q E' M' -∗ ⌜ E' ⊑ E ⌝;
  SeqLocal_lookup :
    ∀ N γg q E M e V,
      sync <$> E !! e = Some V → e ∈ M → SeqLocal N γg q E M -∗ ⊒V;
  SeqLocal_Persistent :
    ∀ N γg q E M, Persistent (SeqLocal N γg q E M);

  SeqPerm_Objective : ∀ γg q ty P, Objective (SeqPerm γg q ty P);
  SeqPerm_Equiv : ∀ γg q ty P1 P2, (∀ n, P1 n = P2 n) → SeqPerm γg q ty P1 -∗ SeqPerm γg q ty P2;
  SeqPerm_Split : ∀ γg q ty P1 P2, SeqPerm γg q ty P1 -∗ SeqPerm γg q ty (λ n, P1 n && P2 n) ∗ SeqPerm γg q ty (λ n, P1 n && negb (P2 n));
  SeqPerm_Combine : ∀ γg q ty P1 P2, SeqPerm γg q ty P1 -∗ SeqPerm γg q ty P2 -∗ SeqPerm γg q ty (λ n, P1 n || P2 n);
  SeqPerm_Excl : ∀ γg q ty P1 P2 n, P1 n = true → P2 n = true → SeqPerm γg q ty P1 -∗ SeqPerm γg q ty P2 -∗ False;
  (**************************************************************)

  (* operations specs *)
  new_seq_spec : new_seq_spec' newSEQ SeqLocal SeqInv SeqPerm;
  enqueueWithTicket_spec : enqueueWithTicket_spec' enqueueWithTicket SeqLocal SeqInv SeqPerm;
  dequeueWithTicket_spec : dequeueWithTicket_spec' dequeueWithTicket SeqLocal SeqInv SeqPerm;
}.

Arguments seq_spec _ {_}.
Global Existing Instances SeqInv_Objective SeqLocal_Persistent SeqPerm_Objective.
