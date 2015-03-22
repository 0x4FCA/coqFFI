(** Reification is the mechanism used to transmit values from OCaml to Coq. *)
Require Import Setoid.
Require Import NArith PArith ZArith.
Require Import Ascii String.
Require Import List.

Set Implicit Arguments.

Import ListNotations.

(** A S-expression, basically a binary tree, can reify almost any data value. *)
Module SExpr.
  Inductive t: Type :=
  | I: t
  | B: t -> t -> t.
End SExpr.

(** A reifiable type is a type equipped with reification functions. *)
Module Reifiable.
  Import SExpr.
  
  Class t (T: Type): Type := New {
    Export: T -> SExpr.t;
    Import: SExpr.t -> T}.
  
  (** We expect to get the original value from a reified one. *)
  Definition IsSound (T: Type) (r: t T): Prop :=
    forall (v: T), Import (Export v) = v.
  
  (** If we can reify [A] to [B] and reify [B], then we can reify [A]. *)
  Definition Morphism (A B: Type) (r: t B)
    (export: A -> B) (import: B -> A): t A := New
    (fun a => Export (export a))
    (fun s => import (Import s)).
  
  (** [unit] is reifiable. *)
  Instance Unit: t unit := New
    (fun _ => I)
    (fun _ => tt).
  
  (** [bool] is reifiable. *)
  Instance Bool: t bool := New
    (fun b =>
      match b with
      | false => I
      | true => B I I
      end)
    (fun s =>
      match s with
      | I => false
      | _ => true
      end).
  
  (** [positive] is reifiable. *)
  Instance BinPos: t positive := New
    (fix export n :=
      match n with
      | xH => I
      | xO n' => B I (export n')
      | xI n' => B (B I I) (export n')
      end)
    (fix import s :=
      match s with
      | I => xH
      | B I s' => xO (import s')
      | B _ s' => xI (import s')
      end).
  
  (** [N] is reifiable. *)
  Instance BinNat: t N := New
    (fun n =>
      match n with
      | N0 => I
      | Npos pos => B I (Export pos)
      end)
    (fun s =>
      match s with
      | I => N0
      | B _ s' => Npos (Import s')
      end).
  
  Instance Z : t Z := New
    (fun z =>
       match z with
       | Z0 => I
       | Zpos pos => B I (Export pos)
       | Zneg pos => B (B I I) (Export pos)
       end)
    (fun s =>
       match s with
       | I => Z0
       | B I s' => Zpos (Import s')
       | B _ s' => Zneg (Import s')
       end).
  
  (** [nat] is reifiable. We do a binary encoding. *)
  Instance Nat: t nat :=
    Morphism BinNat N.of_nat N.to_nat.
  
  (** A product type is reifiable. *)
  Instance Product (T1 T2: Type) `{r1: t T1} `{r2: t T2}
    : t (T1 * T2) := New
    (fun v =>
      B (Export (fst v)) (Export (snd v)))
    (fun s =>
      match s with
      | I => (Import I, Import I)
      | B s1 s2 => (Import s1, Import s2)
      end).
  
  (** A sum type is reifiable. *)
  Instance Sum (T1 T2: Type) `{r1: t T1} `{r2: t T2}
    : t (T1 + T2) := New
    (fun v =>
      match v with
      | inl v' => B I (Export v')
      | inr v' => B (B I I) (Export v')
      end)
    (fun v =>
      match v with
      | I => inl (Import I)
      | B I s' => inl (Import s')
      | B _ s' => inr (Import s')
      end).
  
  (** A list is reifiable. *)
  Instance List (T: Type) `{r: t T}
    : t (list T) := New
    (fix export v :=
      match v with
      | nil => I
      | cons x v' => B (Export x) (export v')
      end)
    (fix import s :=
      match s with
      | I => nil
      | B s1 s2 => cons (Import s1) (import s2)
      end).

  Instance Ascii : t ascii := Morphism (List _)
    (fun a => let 'Ascii a1 a2 a3 a4 a5 a6 a7 a8 := a in [a1;a2;a3;a4;a5;a6;a7;a8])
    (fun l => match l with [a1;a2;a3;a4;a5;a6;a7;a8] => Ascii a1 a2 a3 a4 a5 a6 a7 a8 | _ => zero end).

  Instance String : t string := New
    (fix export v :=
      match v with
      | EmptyString => I
      | String x v' => B (Export x) (export v')
      end)
    (fix import s :=
      match s with
      | I => EmptyString
      | B s1 s2 => String (Import s1) (import s2)
      end).

  Instance option (T : Type) `{t T} : t (option T) := New
    (fun o =>
       match o with
       | None => I
       | Some x => B I (Export x)
       end)
    (fun s =>
       match s with
       | B I v => Some (Import v)
       | _ => None
     end).

Definition pack3 (x y z : SExpr.t) :=
  B (B x y) z.

Definition export2 T U `{Reifiable.t T, Reifiable.t U} (x : T) (y : U) :=
  B (Export x) (Export y).

Definition export3 T U V `{Reifiable.t T, Reifiable.t U, Reifiable.t V} (x : T) (y : U) (z : V) :=
  pack3 (Export x) (Export y) (Export z).

Definition export4 T U V W `{Reifiable.t T, Reifiable.t U, Reifiable.t V, Reifiable.t W}
                   (w : T) (x : U) (y : V) (z : W) :=
  B (pack3 (Export w) (Export x) (Export y)) (Export z).
  
  (** The above definitions are sound. *)
  Module Facts.
    Lemma MorphismIsSound: forall (A B: Type) (r: t B)
      (export: A -> B) (import: B -> A),
      (forall (v: A), import (export v) = v) -> IsSound r ->
      IsSound (Morphism r export import).
      intros A B r export import Ha Hr v.
      simpl.
      now rewrite Hr.
    Qed.
    
    Lemma UnitIsSound: IsSound Unit.
      intro v.
      now destruct v.
    Qed.
    
    Lemma BoolIsSound: IsSound Bool.
      intro v.
      now destruct v.
    Qed.
    
    Lemma BinPosIsSound: IsSound BinPos.
      intro v.
      induction v; trivial;
      now rewrite <- IHv at 2.
    Qed.
    
    Lemma BinNatIsSound: IsSound BinNat.
      intro v.
      destruct v; trivial.
      simpl.
      now rewrite BinPosIsSound.
    Qed.
    
    Lemma NatIsSound: IsSound Nat.
      intro v.
      unfold Nat.
      rewrite MorphismIsSound; trivial.
        exact Nat2N.id.
        
        exact BinNatIsSound.
    Qed.
    
    Lemma ProductIsSound: forall (T1 T2: Type) (r1: t T1) (r2: t T2),
      IsSound r1 -> IsSound r2 -> IsSound (Product T1 T2).
      intros T1 T2 r1 r2 H1 H2 v.
      destruct v as [v1 v2].
      simpl.
      now rewrite H1; rewrite H2.
    Qed.
    
    Lemma SumIsSound: forall (T1 T2: Type) (r1: t T1) (r2: t T2),
      IsSound r1 -> IsSound r2 -> IsSound (Sum T1 T2).
      intros T1 T2 r1 r2 H1 H2 v.
      destruct v as [v1 | v2]; simpl.
        now rewrite H1.
        
        now rewrite H2.
    Qed.
    
    Lemma ListIsSound: forall (T: Type) (r: t T),
      IsSound r -> IsSound (List T).
      intros T r H v.
      induction v; trivial.
      rewrite <- IHv at 2.
      simpl.
      now rewrite H.
    Qed.
  End Facts.

End Reifiable.
