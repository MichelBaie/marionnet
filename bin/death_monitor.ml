(* This file is part of Marionnet, a virtual network laboratory
   Copyright (C) 2007, 2008, 2009  Luca Saiu
   Copyright (C) 2010, 2020  Jean-Vincent Loddo
   Copyright (C) 2007, 2008, 2009, 2010, 2020  Université Paris 13

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

(** This functionality allows the user to register a callback to invoke in the event of
    the unexpected death of each given process. When a process death is detected
    the callback is invoked, and the process is automatically un-registered.
    Process death is not detected immediately, as the implementation is based on
    polling. *)

(* --- *)
module Log = Marionnet_log
module UnixExtra = Ocamlbricks.UnixExtra
(* --- *)
type process_name = string                      (* name of the executable program we're monitoring *)
type pid = int                                  (* process identifier *)
(* --- *)
type predicate = (pid -> bool)                  (* how to check whether we should invoke the callback *)
type callback  = (pid -> process_name -> unit)  (* the callback *)


(** Define an associative map with pids as keys: *)
module Map = Map.Make(struct  type t = pid  let compare = compare  end)
type map = ( process_name * predicate * callback) Map.t

let linearize_map (map : map) =
  Map.fold
    (fun (pid : int) (name, predicate, thunk) list ->
      (pid, (name, predicate, thunk)) :: list)
    map
    []

(** A map mapping each pid into the callback to invoke when the process dies: *)
let processes_to_be_monitored : map ref = ref Map.empty
let poll_interval = ref 1.0 (* in seconds *)
let map_size = ref 0

(** The death_monitor_mutex protecting processes_to_be_monitored from concurrent accesses,
    poll_interval and map_size: *)
let death_monitor_mutex = Mutex.create ()

(** Return true iff we are currently monitoring the given process. Not thread-safe, only
    for internal use *)
let __are_we_monitoring pid =
  Map.mem pid !processes_to_be_monitored

(** Return true iff we are currently monitoring the given process.*)
let are_we_monitoring pid =
  Mutex.lock (death_monitor_mutex);
  let result = __are_we_monitoring pid in
  Mutex.unlock (death_monitor_mutex);
  result

(** The predefined predicate returning true if we should invoke the callback: *)
let default_predicate pid =
   not (UnixExtra.is_process_alive pid)

(** Start monitoring the process with the given pid. Call the given function if
    it ever dies, using the pid and process name as its parameters. This is
    thread-safe. *)
let start_monitoring ?(predicate=default_predicate) pid name callback =
  Mutex.lock death_monitor_mutex;
  (if Map.mem pid !processes_to_be_monitored then begin
    Log.printf1 "WARNING (THIS MAY BE SERIOUS): death_monitor: I was already monitoring %d\n" pid;
  end
  else begin
    processes_to_be_monitored :=
      Map.add pid (name, predicate, callback) !processes_to_be_monitored;
    map_size := !map_size + 1;
    (* We don't want to create zombies: let's asynchronously call waitpid on the process; this is
       important, otherwise other implementation of is_process_alive using kill with a 0 value for
       the signal will see the process as existing. *)
    let _ =
      Thread.create
        (fun () -> UnixExtra.Process.waitpid_non_intr ~wait_flags:[] pid)
        () in
    ();
  end);
  Mutex.unlock (death_monitor_mutex)

(** Stop monitoring the process with the given pid. Not thread-safe, only for
    internal use. Users should call stop_monitoring instead. *)
let __stop_monitoring pid =
  if Map.mem pid !processes_to_be_monitored then begin
    processes_to_be_monitored := Map.remove pid !processes_to_be_monitored;
    map_size := !map_size - 1;
  end
  else begin
    Log.printf1 "WARNING: death_monitor: I was not monitoring %d\n" pid;
  end

(** Stop monitoring the process with the given pid. Thread-safe. *)
let stop_monitoring pid =
  Mutex.lock death_monitor_mutex;
  try
    __stop_monitoring pid;
    Mutex.unlock death_monitor_mutex;
  with e -> begin
    (* Don't leave the death_monitor_mutex locked when raising: *)
    Mutex.unlock death_monitor_mutex;
    (* Re-raise: *)
    Log.printf1 "stop_monitoring: re-raising %s.\n" (Printexc.to_string e);
    raise e;
  end

(** Check the status of all processes which were registered, and invoke callbacks
    if needed. Thread-safe, but only for internal use. *)
let poll () =
  Mutex.lock death_monitor_mutex;
  let thunks =
    List.map
      (fun (pid, (name, predicate, callback)) ->
        (fun () ->
          try if predicate pid then
            (* Only invoke the callback if we are *still* monitoring the process. Of
               processes tend to die in clusters, due to the fact that we often kill
               ALL the processes implementing a device if any single one fails. *)
            if are_we_monitoring pid then
              callback pid name
          with _ ->
            ()))
      (linearize_map !processes_to_be_monitored) in
  Mutex.unlock death_monitor_mutex;
  List.iter
    (fun thunk -> thunk ())
    thunks

(** Update the poll interval length, which will become effective after the current
    poll intervall expires. Using a zero or negative parameter causes the polling
    loop to terminate. Thread-safe. *)
let set_poll_interval seconds =
  Mutex.lock death_monitor_mutex;
  poll_interval := seconds;
  Mutex.unlock death_monitor_mutex

(** Get the current poll interval. Thread-safe. *)
let get_poll_interval seconds =
  Mutex.lock death_monitor_mutex;
  let result = !poll_interval in
  Mutex.unlock death_monitor_mutex;
  result

let rec poll_in_a_loop interval_length =
  if interval_length <= 0.0 then begin
    Log.printf "Exiting from the infinite polling loop.\n";
  end
  else begin
    poll ();
    (try
      Thread.delay interval_length;
    with _ ->
      ()); (* we don't care very much if sleep is interrupted by a signal *)
    let interval_length = get_poll_interval () in
    poll_in_a_loop interval_length;
  end

(** Start polling in a loop: *)
let start_polling_loop () =
  Log.printf "Starting the infinite polling loop.\n";
  poll_in_a_loop (get_poll_interval ())

(** Stop polling (at the end of the current interval). This version locks
    death_monitor_death_monitor_mutex, so it is thread safe. *)
let stop_polling_loop () =
  Log.printf "Stopping the infinite polling loop (locked).
If the program hangs at this point then you are probably using the
locked version within a callback. See the comment in death_monitor.ml .\n";
  set_poll_interval (-1.0)

(** See the comment before stop_polling_loop. Non thread-safe. *)
let __stop_polling_loop () =
  Log.printf "Stopping the infinite polling loop (non-locked).\n";
  poll_interval := -1.0 (* this does not touch the death_monitor_mutex *)

let _ =
  Thread.create
    (fun () -> start_polling_loop ())
    ()
