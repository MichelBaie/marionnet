(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2009, 2010  Jean-Vincent Loddo
   Copyright (C) 2007, 2009  Luca Saiu
   Copyright (C) 2007, 2009, 2010  Université Paris 13

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>. *)

(** All dialogs are implemented here. This module provide the capability for user
    to talk with the application. Specifically, the name "Talking" stands here
    for "Talking with user". *)

#load "include_as_string_p4.cmo"
;;

(* --- *)
module Log = Marionnet_log
module StrExtra = Ocamlbricks.StrExtra
module UnixExtra = Ocamlbricks.UnixExtra
module Environments = Ocamlbricks.Environments
module StringExtra = Ocamlbricks.StringExtra
module Dot = Ocamlbricks.Dot
module Dot_widget = Ocamlbricks.Dot_widget
module Option = Ocamlbricks.Option
module Shell = Ocamlbricks.Shell

(* Alias: *)
type 'a env = 'a Ocamlbricks.Environments.string_env

(** Return the given pathname as it is, if it doesn't contain funny characters
    we don't want to bother supporting, like ' ', otherwise raise an exception.
    No check is performed on the pathname actual existence or permissions: *)
(*let check_pathname_validity pathname =
  if StrExtra.First.matchingp (Str.regexp "^[.a-zA-Z0-9_\\/\\-]+$") pathname then
    pathname
  else
    failwith "The pathname "^ pathname ^" contains funny characters, and we don't support it";;*)

(*let are_there_funny_chars x = not (StrExtra.First.matchingp (Str.regexp "^[.a-zA-Z0-9_\\/\\-]+$") x)
let are_there_funny_chars x = false*)
let are_there_shell_special_chars x = (StrExtra.First.matchingp (Str.regexp "[ )(&*?$]") x)

(** Return true iff the the given directory exists and is on a filesystem supporting
    sparse files. This function doesn't check whether the directory is writable: *)
let does_directory_support_sparse_files pathname =
  (* Funny chars are not allowed because the uml kernel is very strict about filename specifications (ubda=.., ubdb=.., etc) *)
  if are_there_shell_special_chars (pathname) then false else (* continue: *)
  (* All the intelligence of this method lies in the external script, loaded
     at preprocessing time: *)
  let content = INCLUDE_AS_STRING "../../../../bin/scripts/can-directory-host-sparse-files.sh" in
  try
    match UnixExtra.script content [pathname] with
    | (0,_,_) -> true
    |   _     -> false
  with _ -> false
;;

(* Shortcuts *)
let mkenv = Environments.make_string_env ;;

(* **************************************** *
              Module MSG
 * **************************************** *)

open Gettext;;

(** Some tools for building simple help, error, warning and info dialogs *)
module Msg = struct

 (** I moved some stuff into simple_dialogs.ml. It's useful for lots of other
     modules, not only for talking. --L. *)

 (** Specific help constructors*)

 (** Why you have to choose a folder to work *)
 let help_repertoire_de_travail =
   let title = (s_ "CHOOSE A TEMPORARY WORKING DIRECTORY") in
   let msg   = (s_ "Marionnet can use a directory of your choice for its temporary files. \
Every file created in the directory will be deleted at exit time. \
If the program is run from the Marionnet live DVD, you are advised to \
use a persistent directory (in /mnt/hd*), in order to not waste \
your system physical memory.") in Simple_dialogs.help title msg ;;

 let error_saving_while_something_up =
  Simple_dialogs.error
    (s_ "Warning")
   (s_ "The project can't be saved right now. \
One or more network components are still running. \
Please stop them before saving.")
 ;;

 (** Why you have to choose a name for your project *)
 let help_nom_pour_le_projet =
   let title = (s_ "CHOOSE A NAME FOR THE PROJECT") in
   let msg   = (s_ "\
Marionnet saves every files belonging to a project in a file with extension .mar. \
It is a standard gzipped tarball which can also be opened with standard tools.")
   in Simple_dialogs.help title msg ;;
end;; (* module Msg *)

(** Check that the given pathname is acceptable, and that it has the correct extension or
    no extension; if the argument has the correct extension then just return it; it it's
    otherwise valid but has no extension then return the argument with the extension
    appended; if it's invalid or has a wrong extension then show an appropriate
    error message and raise an exception.
    This function is thought as a 'filter' thru which user-supplied filenames should
    be always sent before use. The optional argument extension should be a string with
    *no* dot *)
let check_filename_validity_and_add_extension_if_needed ?identifier ?(extension="mar") path_name =
  let directory = Filename.dirname path_name in
  let correct_extension = "." ^ extension in
  let path_name = Filename.basename path_name in
  let check_chopped_basename_validity chopped_basename =
    if (identifier = None) || StrExtra.Class.identifierp ~allow_dash:() chopped_basename then
      chopped_basename
    else begin
      Simple_dialogs.error
        (s_ "Invalid file name")
        (Printf.sprintf (f_ "The name \"%s\" is not a valid file name.\n\nA valid file \
name must start with a letter and can contain letters, numbers, dashes ('-') and underscores ('_').") chopped_basename)
        ();
      failwith "the given file name is invalid";
    end in
  if Filename.check_suffix path_name correct_extension then
    (* path_name does end with the correct extension; just check that its chopped version is ok: *)
    Printf.sprintf
      "%s/%s%s"
      directory
      (check_chopped_basename_validity (Filename.chop_extension path_name))
      correct_extension
  else
    (* path_name doesn't end with the correct extension: *)
    try
      let _ = Filename.chop_extension path_name in
      (* There is an extension but it's not the correct one; fail: *)
      Simple_dialogs.error
        (s_ "Invalid file extension")
        (Printf.sprintf
           (f_ "The file \"%s\" must have an extension \"%s\", or no extension at all (in which case the extension \"%s\" will be added automatically).")
           path_name
           correct_extension
           correct_extension)
        ();
      failwith ("the given file name has an extension but it's not \"" ^ correct_extension ^ "\".");
    with Invalid_argument _ ->
      (* There is no extension; just check that the filename is otherwise valid, and
         add the extension: *)
      Printf.sprintf
        "%s/%s%s"
        directory
        (check_chopped_basename_validity path_name)
        correct_extension;;


(* **************************************** *
              Module EDialog
 * **************************************** *)


(** An EDialog (for Environnemnt Dialog) is a dialog which may returns an environnement in the
    form (id,value) suitable for functions implementing reactions *)
module EDialog = struct

(** An edialog is a dialog which returns an env as result if succeed *)
type env = string Environments.string_env
type edialog = unit -> env option

(** Dialog related exceptions. *)
exception BadDialog     of string * string;;
exception StrangeDialog of string * string * (string Environments.string_env);;
exception IncompleteDialog;;

(** The (and) composition of edialogs is again an env option *)
let rec compose (dl:edialog list) () (*: ((('a,'b) Environments.env) option)*) =
  match dl with
  | []  -> raise (Failure "EDialog.compose")
  | [d] -> d ()
  | d::l -> (match d () with
             | None   -> None
             | Some (r:env) -> (match (compose l ()) with
                          | None   -> None
                          | Some z -> Some (Environments.string_env_updated_by r z)
                          )
             )
;;

(** Alias for edialog composition *)
let sequence = compose;;

(** Auxiliary functions for file/folder chooser dialogs *)

let default d = function | None -> d | Some v -> v
;;

(** Filters  *)

let image_filter () =
  let f = GFile.filter ~name:"Images" () in
  f#add_custom [ `MIME_TYPE ]
    (fun info ->
      let mime = List.assoc `MIME_TYPE info in
      StringExtra.is_prefix "image/" mime) ;
  f
;;

(* let all_files     () = let f = GFile.filter ~name:"All" () in (f#add_pattern "*"); f ;; *)
let all_files     () = GFile.filter ~name:"All" () ~patterns: ["*"] ;;
let script_filter () = GFile.filter ~name:"Scripts Shell/Python (*.sh *.py)"  ~patterns:[ "*.sh"; "*.py" ] () ;;
let bash_filter   () = GFile.filter ~name:"Bash Scripts (*.sh)"  ~patterns:[ "*.sh"; "*.rc" ] () ;;
let conf_filter   () = GFile.filter ~name:"Configuration files (*.conf *.config)"  ~patterns:[ "*.conf"; "*.config" ] () ;;
let rc_filter     () = GFile.filter ~name:"Read command (*.rc)"  ~patterns:[ "*.rc" ] () ;;
let mar_filter    () = GFile.filter ~name:"Marionnet projects (*.mar)" ~patterns:[ "*.mar"; ] () ;;
let xml_filter    () = GFile.filter ~name:"XML files (*.xml)" ~patterns:[ "*.xml"; "*.XML" ] () ;;
let txt_filter    () = GFile.filter ~name:"Text files (*.txt)" ~patterns:[ "*.txt"; "*.TXT" ] () ;;
let jpeg_filter   () = GFile.filter ~name:"JPEG files (*.jpg *.jpeg)" ~patterns:[ "*.jpg"; "*.JPG"; "*.jpeg"; "*.JPEG" ] ();;
let png_filter    () = GFile.filter ~name:"PNG files (*.png)" ~patterns:[ "*.png"; "*.PNG" ] () ;;

(** Filters for Marionnet *)
type filter_name = [ `ALL | `DOT of Dot.output_format | `IMG | `JPEG | `MAR | `PNG | `SCRIPT | `BASH | `CONF | `RC | `TXT | `XML ];;

(** The kit of all defined filters *)
let allfilters : filter_name list =
  [ `ALL ; `MAR ; `IMG ; `SCRIPT ; `BASH; `CONF; `RC; `TXT; `XML ; `JPEG ]
;;

let get_filter_by_name = function
  | `ALL    -> all_files     ()
  | `MAR    -> mar_filter    ()
  | `IMG    -> image_filter  ()
  | `SCRIPT -> script_filter ()
  | `BASH   -> bash_filter   ()
  | `CONF   -> conf_filter   ()
  | `RC     -> rc_filter     ()
  | `TXT    -> txt_filter    ()
  | `XML    -> xml_filter    ()
  | `JPEG   -> jpeg_filter   ()
  | `PNG    -> png_filter    ()
  | `DOT name -> Dot_widget.filter_of_format name
;;

(* (`vmlz, "vmlz", "Compressed Vector Markup Language (VML)", "XML  document text (gzip compressed data, from Unix)"); *)

(** The edialog asking for file or folder. It returns a simple environment with an unique identifier
    [gen_id] bound to the selected name *)
let ask_for_file
  ?(parent: GWindow.window_skel option)
  ?(enrich=mkenv [])
  ?(title="FILE SELECTION")
  ?(valid:(string->bool)=(fun x->true))
  ?(filter_names = allfilters)
  ?(filters:(GFile.filter list)=[])
  ?(extra_widget:(GObj.widget * (unit -> string)) option)
  ?(action=`OPEN)
  ?(gen_id="filename")
  ?(help=None)()
  =
  let dialog = GWindow.file_chooser_dialog
      ~icon:Icon.icon_pixbuf
      ~action:action
      ~title
      ~modal:true
      ?parent
      ~destroy_with_parent:true
      ()
  in
  dialog#unselect_all ;
  if (help=None) then () else dialog#add_button_stock `HELP `HELP ;
  dialog#add_button_stock `CANCEL `CANCEL ;
  dialog#add_button_stock `OK `OK;
  ignore (dialog#set_current_folder (Initialization.cwd_at_startup_time));
  (* --- *)
  dialog#set_default_response `OK;
  Option.iter (fun (w,r) -> dialog#set_extra_widget w) extra_widget;
  (* --- *)
  if (action=`SELECT_FOLDER)        then (try (dialog#add_shortcut_folder "/tmp") with _ -> ());
  if (action=`OPEN || action=`SAVE) then
    begin
      let filter_list = List.append (List.map get_filter_by_name filter_names) filters in
      List.iter dialog#add_filter filter_list;
    end;
  let result = (ref None) in
  let cont   = ref true in
  while (!cont = true) do
  begin match dialog#run () with
  | `OK -> (match dialog#filename with
              | None   -> ()
              | Some fname ->
                  if (valid fname) then
                    begin
                      cont := false;
                      enrich#add (gen_id,fname);
                      Option.iter (fun (w,reader) -> enrich#add ("extra_widget",reader ())) extra_widget;
                      result := Some enrich
                    end
              )
  | `HELP -> (match help with
              | Some f -> f ();
              | None -> ()
             )
  |  _ -> cont := false
  end
  done;
  (* --- *)
  dialog#destroy ();
  !result
;;


(** The edialog asking for an existing and writable directory. *)
let ask_for_existing_writable_folder_pathname_supporting_sparse_files
 ?(parent: GWindow.window_skel option)
 ?(enrich=mkenv [])
 ?(help=None)
 ~title
 () =
  let valid = fun pathname ->
    (* --- *)
    if (not (Sys.file_exists pathname)) then
      begin
	let () =
	  Simple_dialogs.error
	    (s_ "Invalid directory")
	    (s_ "The directory doesn't exists!\nYou must choose an exiting directory name.")
	    ()
	in
	false
      end
    else (* continue: *)
    (* --- *)
    (* Resolve symlinks which are problematic for starting components: *)
    let pathname = Option.extract (UnixExtra.realpath pathname) in
    (* --- *)
    if (are_there_shell_special_chars pathname) then
      begin
	let () =
	  Simple_dialogs.error
	    (s_ "Invalid directory name")
            (* (Printf.sprintf (f_ "The name \"%s\" is not a valid directory.\n\nDirectory names must contain only letters, numbers, dots, dashes ('-') and underscores ('_').") pathname) *)
	    (Printf.sprintf (f_ "The name \"%s\" contains some shell special chars (blanks, parenthesis,..) which are not allowed.") pathname)
	    ()
	in
	false
      end
    else (* continue: *)
    (* --- *)
    if (not (UnixExtra.dir_rwx_or_link_to pathname)) ||
       (not (does_directory_support_sparse_files pathname)) then
        begin
          let () =
	    Simple_dialogs.error
	      (s_ "Invalid directory")
	      (s_ "Choose a directory which is existing, modifiable and hosted on a filesystem supporting sparse files (ext2, ext3, ext4, reiserfs, NTFS, ...)")
	      ()
	  in
          false
        end
    else true
  in
  ask_for_file ?parent ~enrich ~title ~valid ~filter_names:[] ~action:`SELECT_FOLDER ~gen_id:"foldername" ~help ()


(** The edialog asking for a fresh and writable filename. *)
let ask_for_fresh_writable_filename
  ?(parent: GWindow.window_skel option)
  ?(enrich=mkenv [])
  ~title
  ?(filters:(GFile.filter list) option)
  ?filter_names
  ?(extra_widget:(GObj.widget * (unit -> string)) option)
  ?(help=None)
  =
  let valid x =
    if (Sys.file_exists x)
    then ((Simple_dialogs.error
             (s_ "Name choice")
             (s_ "A file with the same name already exists!\n\nChoose another name for your file.")
             ()); false)
    else (UnixExtra.viable_freshname x)
  in
  let result =
    ask_for_file ?parent ~enrich ~title ~valid ?filters ?filter_names ?extra_widget ~action:`SAVE ~gen_id:"filename" ~help in
  result;;

let dialog_error_choosed_file_doesnt_exist () =
  Simple_dialogs.error
    (s_ "File choice")
    (s_ "The file doesn't exist!\nYou must choose an existing file name.")
    ()

let dialog_error_choosed_file_is_not_a_text_file () =
  Simple_dialogs.error (s_ "File choice") (s_ "The file is not a text file") ()

let dialog_error_choosed_file_is_too_big_to_be_imported (limit:string) =
  Simple_dialogs.error
    (s_ "File choice")
    (Printf.sprintf (f_ "The file is too big to be imported\nYou must choose a file smaller than %s.") limit)
    ()

let file_size_kb (filename) =
  let s = Unix.stat (filename) in
  (s.Unix.st_size + 1024) / 1024

let is_text_file (filename) =
  if (Sys.command "which file 1>/dev/null 2>/dev/null") <> 0 then true (* we suppose that *) else (* continue: *)
  match Shell.Files.file ~opt:"-L -b --mime-type 2>/dev/null" filename with
  | [answer] -> ((String.sub answer 0 4) = "text")
  | _ -> false

(** The edialog asking for an existing readable/writable filename. *)
let ask_for_existing_rw_filename ?parent ?(enrich=mkenv []) ~title ?(filter_names = allfilters) ?(help=None) () =
  let valid = fun x ->
    if not (Sys.file_exists x) then (dialog_error_choosed_file_doesnt_exist (); false) else (* continue: *)
    UnixExtra.regfile_rw_or_link_to x
  in
  ask_for_file ?parent ~enrich ~title ~valid ~filter_names ~action:`OPEN ~gen_id:"filename" ~help ()
;;

(** The edialog asking for an existing filename which content may be imported as a string. *)
let ask_for_existing_importable_text_filename ?parent ?(enrich=mkenv []) ?(max_size_kb=1024) ~title ?(filter_names = allfilters) ?(help=None) () =
  let valid = fun x ->
    if not (Sys.file_exists x) then (dialog_error_choosed_file_doesnt_exist (); false) else (* continue: *)
    if not (is_text_file x)    then (dialog_error_choosed_file_is_not_a_text_file (); false) else (* continue: *)
    let size_kb = file_size_kb x in
    if not (size_kb < max_size_kb) then (dialog_error_choosed_file_is_too_big_to_be_imported ((string_of_int max_size_kb)^" Kb"); false) else (* continue: *)
    UnixExtra.regfile_r_or_link_to x (* Just readable *)
  in
  ask_for_file ?parent ~enrich ~title ~valid ~filter_names ~action:`OPEN ~gen_id:"filename" ~help ()
;;

(** Generic constructor for question dialogs.
    With the 'enrich' optional parameter the dialog can enrich a given environnement. Otherwise
    it creates a new one. *)
let ask_question ?(enrich=mkenv []) ?(title="QUESTION") ?(gen_id="answer") ?(help=None) ?(cancel=false) ~(question:string)  () =

   let dialog=new Gui.dialog_QUESTION () in

   if (help=None)    then () else dialog#toplevel#add_button_stock `HELP   `HELP ;
   if (cancel=false) then () else dialog#toplevel#add_button_stock `CANCEL `CANCEL ;

   dialog#toplevel#set_title title;
   dialog#title_QUESTION#set_use_markup true;
   dialog#title_QUESTION#set_label question;
   ignore
     (dialog#toplevel#event#connect#delete
        ~callback:(fun _ -> Log.printf "Sorry, no, you can't close the dialog. Please make a decision.\n"; true));

   let result = (ref None) in
   let cont   = ref true in
   while (!cont = true) do
     match dialog#toplevel#run () with
     | `YES  -> begin cont := false; enrich#add (gen_id,"yes"); result := Some enrich end
     | `NO   -> begin cont := false; enrich#add (gen_id,"no" ); result := Some enrich end
     | `HELP -> (match help with
                 | Some f -> f ();
                 | None -> ()
             )
     | `CANCEL when cancel -> begin
         cont := false;
         result := None
       end
     | _ ->
       cont := true; (* No, the user has to make a decision *)
   done;
   dialog#toplevel#destroy ();
   !result

;;


end;; (* EDialog *)
