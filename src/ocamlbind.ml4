open Tactics
open Tacticals
open Refiner
open Tacmach

open OcamlbindConstants
open OcamlbindState

(** Use site configuration to determine where Cybele
    is installed. *)
let coqlib =
  Filename.concat (Filename.concat (Envars.coqlib ()) "user-contrib") "OCamlBind"

(** Use site configuration to use the right ocaml native compilers. *)
let ocamlopt = Envars.ocamlopt ()

(** Use site configuration to use the right ocaml bytecode compilers. *)
let ocamlc = Envars.ocamlc ()

(** [command s] runs [s] and logs the exit status. *)
let command s =
  let ret = Sys.command s in
  Pp.msg (Pp.str (Printf.sprintf "OCamlBind [%d]: %s\n" ret s))

let cleanup fname =
  command (Printf.sprintf "rm %s" fname)

(** compile [c] returns a compiled version of the monadic computation [c]
    in the form of an Ocaml module. *)
let compile c =
  print_endline message;
  let rec compile () =
    (** The compilation is the composition of the Coq extraction
        with the compilation from ocaml to the right low-level
        plateform (native or bytecode).

        The extraction uses a temporary definition that is automatically
        cleaned up using the Coq's rollback mechanism.
    *)
    ocaml_compiler (States.with_state_protection ocaml_via_extraction ())

  and ocaml_via_extraction () =
    (** Name [c]. *)
    (** Extract [c] in a file and all its dependencies. *)
    let tmp      = Filename.temp_file "cybele" ".ml" in
    let tmp_intf = Filename.chop_extension tmp ^ ".mli" in
    Extract_env.full_extraction (Some tmp) [c];
    (** We are not interested in the interface file. *)
    cleanup tmp_intf;
    tmp

  and ocaml_compiler fname =
    (** Use a temporary file for the compiled module. *)
    let compiled_module =
      let basename = Filename.temp_file "cybele_dyn" "" in
      fun ext -> basename ^ "." ^ ext 
    in
    (** Compile using the right compiler. *)
    if Dynlink.is_native then (
        let target  = compiled_module "cmx" in
        let target' = compiled_module "cmxs" in
        command (Printf.sprintf
                   "%s -rectypes -c -I %s -o %s %s"
                   ocamlopt coqlib target fname);
        command (Printf.sprintf
                   "%s -shared -o %s %s"
                   ocamlopt target' target);
        (target', [target; target'])
    ) else (
      let target = compiled_module "cmo" in
        command (Printf.sprintf 
                   "%s -rectypes -c -linkall -I %s -o %s %s/cybelePlugin.cma %s"
                   ocamlc coqlib target coqlib fname);
        (target, [target])
    )
  in
  compile ()

let dynload f =
  try
    Dynlink.loadfile f
  with Dynlink.Error e ->
    Errors.error ("OCamlBind (during compiled code loading):"
                   ^ (Dynlink.error_message e))

let solve_remaining_apply_goals =
  Proofview.Goal.nf_enter begin fun gl ->
    try 
      let env = Proofview.Goal.env gl in
      let sigma = Proofview.Goal.sigma gl in
      let concl = Proofview.Goal.concl gl in
      if Typeclasses.is_class_type sigma concl then
        let evd', c' = Typeclasses.resolve_one_typeclass env sigma concl in
    Tacticals.New.tclTHEN
          (Proofview.Unsafe.tclEVARS evd')
          (Proofview.V82.tactic (refine_no_check c'))
    else Proofview.tclUNIT ()
    with Not_found -> Proofview.tclUNIT ()
  end

let ocamlbind f a x =
  Proofview.Goal.nf_enter begin fun gl ->
    let env = Proofview.Goal.env gl in
    let path = Nametab.path_of_global a in
    let qid = Libnames.qualid_of_path path in
    let a = Libnames.Qualid (Loc.dummy_loc, qid) in
    let dyncode, files = compile a in
    dynload dyncode;
    let output = get_output () in
    let t1 = apply (Lazy.force Reifiable.import) in
    Tacticals.New.tclTHENLIST [ t1; solve_remaining_apply_goals]
  end

let _ = register_fun "id" (fun x -> x)

DECLARE PLUGIN "ocamlbindPlugin"

TACTIC EXTEND ocamlbind
  [ "ocamlbind" string(f) global(a) constr(x) ] -> [ ocamlbind f a x ]
END
