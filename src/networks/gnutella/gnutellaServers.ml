(* Copyright 2001, 2002 b8_bavard, b8_fee_carabine, INRIA *)
(*
    This file is part of mldonkey.

    mldonkey is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    mldonkey is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with mldonkey; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*)

open Queues
open Printf2
open Md4
open BasicSocket
open TcpBufferedSocket
open Options
  
open CommonSwarming
open CommonOptions
open CommonSearch
open CommonServer
open CommonComplexOptions
open CommonFile
open CommonTypes
open CommonGlobals
open CommonHosts
  
open MultinetTypes
open MultinetFunctions
open MultinetComplexOptions
  
open GnutellaTypes
open GnutellaGlobals
open GnutellaOptions
open GnutellaProtocol
open GnutellaComplexOptions

module DG = CommonGlobals
module DO = CommonOptions
  
module GnutellaHandler = struct
    let init s sock gconn =
      Gnutella1Handler.init s sock gconn
  end
  
let gnutella_proto = "GNUTELLA/"
let gnutella_proto_len = String.length gnutella_proto

let retry_and_fake = false
  
let rec server_parse_header retry_fake s gconn sock header
  =
(*   if !verbose_msg_servers then  LittleEndian.dump_ascii header;   *)
  try
    if not (String2.starts_with header gnutella_proto) then 
      failwith "Reply is not in gnutella protocol";
    let space_pos = String.index header ' ' in
    let proto = String.sub header gnutella_proto_len (
        space_pos - gnutella_proto_len) in
    let code = String.sub header (space_pos+1) 3 in
    let lines = Http_client.split_header header in
    let headers =        
      match lines with
        [] -> []
      | line :: headers ->
          let headers = Http_client.cut_headers headers in
          if !verbose_msg_servers then begin
              lprintf "HEADER: %s\n" line;
              List.iter (fun (header, (value,_)) ->
                  lprintf "   %s = %s\n" header value;
              ) headers;
              lprintf "\n\n"
            end; 
          headers          
    in
    
    let ultra_peer = ref false in
    let gnutella2 = ref false in
    let deflate = ref false in
    let keep_headers = ref [] in
    let content_type = ref "" in
    let x_ultrapeers = ref [] in
    List.iter (fun (header, (value, key)) ->
        try
          match (String.lowercase header) with
          
          | "user-agent" ->  
              s.server_agent <- value;
              keep_headers := (key, value) :: !keep_headers
          
          | "remote-ip" -> 
              last_high_id := Ip.of_string value;

(* Be careful with x-try when we will limit the number of ultra_peers *)
(*          | "x-try" *)
          | "x-try-ultrapeers" ->
              List.iter (fun s ->
                  try
                    let len = String.length s in
(*                    lprintf "NEW ULTRAPEER %s\n" s; *)
                    let pos = String.index s ':' in
                    let ip = String.sub s 0 pos in
                    let port = try
                        let space = String.index_from s pos ' ' in
                        String.sub s (pos+1) (space - pos -1)
                      with _ -> 
                          String.sub s (pos+1) (len - pos - 1) in
                    let ip = Ip.of_string ip in
                    let port = int_of_string port in
(*                    lprintf "ADDING UP %s:%d\n" (Ip.to_string ip) port;  *)
                    x_ultrapeers :=  (ip,port, true) :: !x_ultrapeers;
                  with e -> 
                      lprintf "Could not parse x-try-ultrapeers (%s):\n"
                        (Printexc2.to_string e);
                      AnyEndian.dump s
              ) (String2.split_simplify value ',')
          
          | "x-try" ->
              List.iter (fun s ->
                  try
                    let len = String.length s in
(*                    lprintf "NEW ULTRAPEER %s\n" s; *)
                    let pos = String.index s ':' in
                    let ip = String.sub s 0 pos in
                    let port = try
                        let space = String.index_from s pos ' ' in
                        String.sub s (pos+1) (space - pos -1)
                      with _ -> 
                          String.sub s (pos+1) (len - pos - 1) in
                    let ip = Ip.of_string ip in
                    let port = int_of_string port in
(*                    lprintf "ADDING UP %s:%d\n" (Ip.to_string ip) port;  *)
                    x_ultrapeers :=  (ip,port, false) :: !x_ultrapeers;
                  
                  with e -> 
                      lprintf "Could not parse x-try (%s):\n"
                        (Printexc2.to_string e);
                      AnyEndian.dump s
              ) (String2.split_simplify value ',')
          
          | "accept" -> ()
          | "accept-encoding" -> ()
          | "x-ultrapeer-loaded" -> ()
          
          | "content-type" ->
              List.iter (fun s ->
                  content_type := s;
                  lprintf "Content-Type: %s\n" s;
                  match s with 
                    "application/x-gnutella2" -> gnutella2 := true
                  | _ -> ()
              ) (String2.split_simplify value ',')
          
          | "x-ultrapeer" ->
              if String.lowercase value = "true" then ultra_peer := true
          
          | "content-encoding" -> 
              if value = "deflate" then deflate := true
          
          | "listen-ip"
          | "x-my-address"
            -> (* value = ip:port *) ()
          | "servent-id" -> (* servent in hexa *) ()
          | "x-ultrapeer-needed" -> (* true/false *) ()
          | "fp-auth-challenge" -> (* used by BearShare for auth *) ()
          | "machine" -> () (* unknown usage *)
(* Swapper *)
          | "x-live-since" -> ()
(* Gtk-gnutella : try and try-ultrapeer on several lines *)
          | "x-token" -> ()
(* Gnucleus/MorpheusOS/MyNapster *)
          | "uptime" -> (*  0D 21H 01M *) ()

(* These ones should be kept *)
          | "x-query-routing"    (* current 0.1 *) 
          | "pong-caching"    (* version = 0.1 *) 
          | "ggep"    (* current is 0.5 *) 
          | "vendor-message"    (* current is 0.1 *) 
          | "bye-packet"    (* current is 0.1 *) 

(* LimeWire *)
          | "x-dynamic-querying"    (* current is 0.1 *) 
          | "x-version"    
          | "x-max-ttl"    (* often 4 *) 
          | "x-degree"    (* often 15 *)  
          | "x-ext-probes"    (* current is 0.1 *) 
          | "x-ultrapeer-query-routing"    (* current is 0.1 *) 
(* BearShare *)
          | "hops-flow"    
          | "bearchat"    
          | "x-guess" ->
              s.server_query_key <- GuessSupport
          | "x-leaf-max" -> 
              keep_headers := (key, value) :: !keep_headers
          
          | _ -> 
              if !verbose_unknown_messages then begin
                  lprintf "Unknown Option in HEADER:\n";
                  List.iter (fun (h, (v,_)) ->
                      if h = header then
                        lprintf ">>>>>>>   %s = %s\n" h v
                      else
                        lprintf "   %s = %s\n" h v;
                  ) headers;
                  lprintf "\n\n"
                end
        with _ -> ()
    ) headers;
    List.iter (fun (ip,port,ultrapeer) ->
        lprintf "gnutella1: adding ultrapeer from %s\n" s.server_agent;
        ignore (H.new_host ip port (ultrapeer))
    ) !x_ultrapeers;    
    server_must_update (as_server s.server_server);
    
    if not !ultra_peer then 
      failwith "DISCONNECT: Not an Ultrapeer";
    if proto < "0.6" then
      failwith (Printf.sprintf "Bad protocol [%s]" proto)
    else
    if code <> "200" then begin
        s.server_connected <- int32_time ();
        if retry_fake then begin
            GnutellaGlobals.disconnect_from_server s
              (Closed_for_error "Bad HTTP code");
            connect_server false s.server_host
              !keep_headers
          end else
          failwith  (Printf.sprintf "Bad return code [%s]" code)
      
      end else
    let msg = 
      let buf = Buffer.create 100 in
      Buffer.add_string buf "GNUTELLA/0.6 200 OK\r\n";
      if !content_type <> "" then
        Printf.bprintf  buf "Content-Type: %s\r\n"
          (if !gnutella2 then
            "application/x-gnutella2" else
            !content_type);
      Buffer.add_string buf "X-Ultrapeer: False\r\n";
(* Contribute: sending gnutella 1 or 2 ultrapeers to other peers
      Buffer.add_string "X-Try-Ultrapeers: ...\r\n"; *)
      if !deflate then
        Printf.bprintf buf "Content-Encoding: deflate\r\n";
      Buffer.add_string buf "\r\n";
      Buffer.contents buf
    in
    if !verbose_msg_servers then
      lprintf "CONNECT REQUEST: %s\n" (String.escaped msg); 
    write_string sock msg;

(*
    if not retry_fake then
      lprintf "******** CONNECTED BY FAKING ********\n";
*)
    
    set_rtimeout sock DG.half_day;
    set_server_state s (Connected (-1));
    s.server_connected <- int32_time ();    
    Gnutella1Handler.init s sock gconn;
  
  with
  | e -> 
      if !verbose_msg_servers then
        lprintf "DISCONNECT WITH EXCEPTION %s\n" (Printexc2.to_string e); 
      disconnect_from_server s (Closed_for_exception e)

and connect_server retry_fake h headers =  
  let s = match h.host_server with
      None -> 
        let s = new_server h.host_addr h.host_port in
        h.host_server <- Some s;
        s
    | Some s -> s
  in
  match s.server_sock with
    ConnectionWaiting -> ()
  | ConnectionAborted -> s.server_sock <- ConnectionWaiting
  | Connection _ | CompressedConnection _ -> ()
  | NoConnection -> 
      incr g1_nservers;
      s.server_sock <- ConnectionWaiting;
      add_pending_connection (fun _ ->
          decr g1_nservers;
          match s.server_sock with
            ConnectionAborted -> s.server_sock <- NoConnection;
          | Connection _ | NoConnection | CompressedConnection _ -> ()
          | ConnectionWaiting ->
              try
                if not (Ip.valid s.server_host.host_addr) then
                  failwith "Invalid IP for server\n";
                let ip = s.server_host.host_addr in
                let port = s.server_host.host_port in
(*        if !verbose_msg_servers then begin
            lprintf "CONNECT TO %s:%d\n" (Ip.to_string ip) port;
end;  *)
                H.set_request h Tcp_Connect;
                let sock = connect "gnutella to server"
                    (Ip.to_inet_addr ip) port
                    (fun sock event -> 
                      match event with
                        BASIC_EVENT (RTIMEOUT|LTIMEOUT) -> 
(*                  lprintf "RTIMEOUT\n"; *)
                          disconnect_from_server s Closed_for_timeout
                      | _ -> ()
                  ) in
                TcpBufferedSocket.set_read_controler sock download_control;
                TcpBufferedSocket.set_write_controler sock upload_control;
                
                set_server_state s Connecting;
                s.server_sock <- Connection sock;
                incr g1_nservers;
                set_gnutella_sock sock !verbose_msg_servers
                  (HttpHeader (server_parse_header retry_fake s)
                
                );
                set_closer sock (fun _ error -> 
(*            lprintf "CLOSER %s\n" error; *)
                    disconnect_from_server s error);
                set_rtimeout sock !!server_connection_timeout;
                
                let s = 
                  let buf = Buffer.create 100 in
(* Start by Gnutella2 headers *)
                  Buffer.add_string buf "GNUTELLA CONNECT/0.6\r\n";
                  Printf.bprintf buf "Listen-IP: %s:%d\r\n"
                    (Ip.to_string (client_ip (Connection sock))) !!client_port;
                  Printf.bprintf buf "Remote-IP: %s\r\n"
                    (Ip.to_string s.server_host.host_addr);
                  
                  if headers = [] then begin
                      Printf.bprintf buf "User-Agent: %s\r\n" user_agent;
(* Contribute:  Packet compression is not yet supported...
Printf.bprintf buf "Accept-Encoding: deflate\r\n"; *)
(* Other Gnutella headers *)          
                      Printf.bprintf buf "X-Max-TTL: 4\r\n";
                      Printf.bprintf buf "Vendor-Message: 0.1\r\n";
                      Printf.bprintf buf "X-Query-Routing: 0.1\r\n";
(* We add these two headers for Limewire, we are not completely sure we
  can comply with, as we are not ultrapeers... *)
                      
                      Printf.bprintf buf "X-Dynamic-Querying: 0.1\r\n";
                      Printf.bprintf buf "X-Ultrapeer-Query-Routing: 0.1\r\n";

(* Guess support will be enabled soon *)
                      Printf.bprintf buf "X-Guess: 0.1\r\n";
(* We don't forward Pongs at all, so we have this header... *)
                      Printf.bprintf buf "Pong-Caching: 0.1\r\n";
                      Printf.bprintf buf "Bye-Packet: 0.1\r\n";
                      Printf.bprintf buf "GGEP: 0.5\r\n"; 
(* We never forward messages, so all our messages have hops = 0 *)
                      Printf.bprintf buf "Hops-Flow: 0.1\r\n"; 
(* Don't really know what this header means, so we just put the number
of ultrapeers we want to connect to *)
                      Printf.bprintf buf "X-Degree: %d\r\n" !!g1_max_ultrapeers;   
                      Printf.bprintf buf "X-Guess: 0.1\r\n";  
                    end else begin
(*              lprintf "****** Retry and fake **********\n"; *)
                      List.iter (fun (key, value) ->
                          Printf.bprintf buf "%s: %s\r\n" key value
                      ) headers;
                    end;
                  Printf.bprintf buf "X-My-Address: %s:%d\r\n"
                    (Ip.to_string (client_ip (Connection sock))) !!client_port;
                  Printf.bprintf buf "X-Ultrapeer: False\r\n";
                  Printf.bprintf buf "X-Ultrapeer-Needed: True\r\n";
(* Finish with headers *)
                  Buffer.add_string buf "\r\n";
                  Buffer.contents buf
                in
                if !verbose_msg_servers then
                  lprintf "SENDING %s\n" (String.escaped s);
                write_string sock s;
              with e ->
                  disconnect_from_server s
                    (Closed_for_exception e)
      )      

let get_file_from_source c file =
  if connection_can_try c.client_connection_control then begin
      connection_try c.client_connection_control;
      match c.client_user.user_kind with
        Indirect_location ("", uid) ->
          lprintf "++++++ ASKING FOR PUSH +++++++++\n";   

(* do as if connection failed. If it connects, connection will be set to OK *)
          connection_failed c.client_connection_control;

          let uri = (find_download file c.client_downloads).download_uri in
          List.iter (fun s ->
              Gnutella1Proto.server_send_push s uid uri
          ) !g1_connected_servers;
      | _ ->
          GnutellaClients.connect_client c
    end

let exit = Exit
  
let recover_file file = 
  
  List.iter (fun fuid ->
      try
        List.iter (fun s ->
            match s.search_search with
              FileUidSearch (ss,uid) when uid = fuid -> raise exit
            | _ -> ()
        ) file.file_searches;
        
        let s = {
          search_search = FileUidSearch (file, fuid);
          search_hosts = Intset.empty;
          search_uid = Md4.random ();          
          }  in
        
        Hashtbl.add searches_by_uid s.search_uid s;
        file.file_searches <- s :: file.file_searches
      with _ -> ()
  ) file.file_shared.file_uids;
  
  Gnutella1.recover_file file;
  ()

let recover_files () =
  List.iter (fun file ->
      recover_file file 
  ) !current_files;
  ()
    
let download_file (r : result) =
    let file_shared = new_download None
      [r.result_name] r.result_size None r.result_uids in
  let new_download = ref None in
  Hashtbl.iter (fun _ file ->
      if file.file_shared = file_shared then
        new_download := Some file
  ) files_by_uid;
  match !new_download with
    None -> () (* The file was probably already downloading *)
  | Some file ->
      new_download := None;
      let file_shared = file.file_shared in
      lprintf "DOWNLOAD FILE %s\n" (file_best_name file_shared); 
      if not (List.memq file !current_files) then begin
          current_files := file :: !current_files;
        end;
      List.iter (fun (user, index) ->
          let c = new_client user.user_kind in
          add_download file c index;
          get_file_from_source c file;
      ) r.result_sources;
      recover_file file;
      ()
  
let disconnect_server s r =
  match s.server_sock with
  | Connection sock -> close sock r
  | ConnectionWaiting -> s.server_sock <- ConnectionAborted
  | _ -> ()
    
let ask_for_files () =
  List.iter (fun file ->
      List.iter (fun c ->
          get_file_from_source c file
      ) file.file_clients
  ) !current_files;
  ()

    
let udp_handler p =
  let (ip,port) = match p.UdpSocket.addr with
    | Unix.ADDR_INET(ip, port) -> Ip.of_inet_addr ip, port
    | _ -> raise Not_found
  in
  let buf = p.UdpSocket.content in
  let len = String.length buf in
  lprintf "Unexpected UDP packet: \n%s\n" (String.escaped buf)
      
let _ =
  server_ops.op_server_disconnect <- (fun s -> disconnect_server s
Closed_by_user);
  server_ops.op_server_remove <- (fun s ->
      disconnect_server s Closed_by_user; 
  )
