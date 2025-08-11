(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008  Luca Saiu
   Copyright (C) 2009, 2010  Jean-Vincent Loddo
   Copyright (C) 2007, 2008, 2009, 2010  Université Paris 13

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

(* --- *)
module Log = Marionnet_log

open Graph;;
open Message_passing;;

let do_in_parallel thunks =
  (* Make a thread per thunk: *)
  let threads =
    List.map
      (fun thunk ->
        Thread.create
          (fun () ->
            try
              thunk ()
            with e -> begin
              Log.printf1 "!!!! do_in_parallel: a thunk failed (%s)\n" (Printexc.to_string e);
            end)
          ())
      thunks in
  (* Wait that they terminate: *)
  List.iter
    (fun thread ->
      try
        Thread.join thread;
      with e -> begin
        Log.printf1 "!!!!!!!!!!!!!!! This should not happen: join failed (%s)\n"
          (Printexc.to_string e);
      end)
    threads;;

(** A thunk is trivially represented a unit->unit function: *)
type thunk =
    unit -> unit;;

(** A task is a thunk, to be executed by the task-runner thread: *)
type task = thunk;;

(** A graph of tasks combines tasks with their dependency relation: *)
(* type task_graph = thunk graph;; *)

(** This is only used internally. *)
exception Kill_task_runner;;

(** This class allows the user to enqueue tasks (represented as thunks) to
    be executed one after another, all in the same thread which is
    created at initialization time. *)
class task_runner = object(self)
  val queue : (string * (unit -> unit)) queue = new queue

  val run_again = ref true

  initializer
(*     (\** Handle SIGCHLD by default: *\) *)
(*     Signals.install_sigchld_handler (); *) (* No, absolutely not! :-) *)
    ignore (Thread.create
              (fun () ->
                while !run_again do
                  Log.printf "task_runner: I'm ready for the next task...\n";
                  let name, task = queue#dequeue in
                  self#run name task;
                done)
              ())

  method run name task =
    flush_all ();
    try
      Log.printf1 "task_runner: Executing the task \"%s\"\n" name;
      task ();
      Log.printf1 "task_runner: The task \"%s\" succeeded.\n" name;
    with Kill_task_runner -> begin
      Log.printf "task_runner: The task runner was explicitly killed.\n";
      run_again := false;
    end
    | e -> begin
      Log.printf2
        "task_runner: WARNING: the asynchronous task \"%s\" raised an exception\n\t(%s).\n\tTHIS MAY BE SERIOUS.\n\tAnyway, I'm going to continue with the next task.\n"
        name
        (Printexc.to_string e) ;
    end

  method schedule ?(name="[unnamed task]") task =
    queue#enqueue (name, task)

  method prepend ?(name="[unnamed task]") task =
    queue#prepend (name, task)

  (** This queue is only used for synchronization purposes. Message-passing
      synchronizations is way spiffier :-) *)
  val dummy_queue : unit queue = new queue

  (** Wait that all tasks which are currently scheduled terminate, synchronously.
      In the mean time more tasks can be scheduled as usual. *)
  method wait_for_all_currently_scheduled_tasks = begin
    let () = if GMain_actor.am_I_the_GTK_main_thread () then
      Log.printf "task_runner#wait_for_all_currently_scheduled_tasks: WARNING: the waiting thread should not be the GTK main thread\n"
    in
    (* --- *)
    let () = self#schedule ~name:"wait until all scheduled tasks terminate" (fun () -> dummy_queue#enqueue ()) in
    (* --- *)
    Log.printf "Waiting for all currently enqueued tasks to terminate...\n";
    let () = dummy_queue#dequeue in
    Log.printf "...all right, we have been signaled: tasks did terminate.\n";
    end

  (* --- *)
  method schedule_parallel (names_and_thunks : (string * thunk) list) =
    let parallel_task_name =
      List.fold_left
        (fun s name -> s ^ name ^ " || ")
        "In parallel: "
        (List.map (fun (name, _) -> name) names_and_thunks)
    in
    let parallel_task_thunk =
      fun () ->
        let threads =
          List.map
            (fun (name, thunk) -> name, Thread.create thunk ())
            names_and_thunks
        in
        threads |> List.iter (fun (name, thread) ->
           Log.printf1 "Joining \"%s\"...\n" name;
           (try
              Thread.join thread;
            with e -> begin
              Log.printf1 "!!!!!!!!!!!!!!! This should not happen: join failed (%s)\n" (Printexc.to_string e);
            end);
           Log.printf1 "I have joined \"%s\" with success\n" name;
           )
    in
    (*  self#schedule ~name:parallel_task_name parallel_task_thunk *)
    self#prepend ~name:parallel_task_name parallel_task_thunk

  (** A user-friendly way to schedule a set of tasks with a dependency graph.
      The description is a list of triples
      <name, list of dependencies as names, thunk>. *)
  method schedule_tasks description =
    let g = make_empty_graph () in
    (* First make the nodes, and a local name -> id table: *)
    let table = Hashtbl.create ((List.length (get_node_ids g)) * 2) in
    List.iter
      (fun (name, _, thunk) ->
        let id = add_node (name, thunk) g in
        Hashtbl.add table name id)
      description;
    (* Now make edges: *)
    List.iter
      (fun (name, dependencies, _) ->
        List.iter
          (fun a_dependency ->
            add_edge
              (Hashtbl.find table name)
              (Hashtbl.find table a_dependency)
              g)
          dependencies)
      description;
    (* Ok, we have the graph. Now we can use it to schedule tasks in some
       reasonable order: *)
    List.iter
      (fun id ->
        let name, thunk = get_node id g in
        self#schedule ~name thunk)
      (topological_sort g)

(*  method terminate =
    self#prepend
      ~name:"Destroying the task runner"
      (fun () -> raise Kill_task_runner)*)
end;;

let the_task_runner =
  new task_runner;;

(*
let g =
  schedule_tasks
    [ "a", [],
      (fun () -> print_string "a\n");
      "b", ["c"],
      (fun () -> print_string "b\n");
      "c", ["a"],
      (fun () -> print_string "c\n"); ];;

let sorted_nodes = topological_sort g;;
let _ =
  List.iter
    (fun id ->
      let name, thunk = get_node id g in
      Log.printf "Executing %s\n" name;
      thunk ();)
    sorted_nodes;;
*)

(* ------------------------------------------------------------------------------------ *)
(* Example: *)
(*
let _ =
  schedule_tasks
    [ "a", [],
      (fun () -> print_string "(a) This will come first.\n");
      "b", ["c"],
      (fun () -> print_string "(b) This will come after c.\n");
      "c", ["a"],
      (fun () -> print_string "(c) This will come after a.\n"); ];;
Unix.sleep 3;;
*)
