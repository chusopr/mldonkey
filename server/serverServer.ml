(* Fonction of server interation in the relais protocol *)
(* Copyright 2002 vernin, INRIA *)
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

(*open Mftp_server*)
open ServerClients
open CommonGlobals
open CommonTypes
open BasicSocket
open TcpBufferedSocket
open Unix
open TcpBufferedSocket
open DonkeyMftp
open Options
open Mftp_comm
open ServerTypes  
open ServerOptions        
open ServerGlobals
open ServerMessages

module M = ServerMessages
  
let null_ip = Ip.of_int32 (Int32.of_int 0)

exception NoSocket

let add_file s md4 ip port =
  s.server_notifications <- {
    add = true;
    md4 = md4;
    source_ip = ip;
    source_port = port;
  } :: s.server_notifications
    
let supp_file s md4 ip port =
  s.server_notifications <- {
    add = false;
    md4 = md4;
    source_ip = ip;
    source_port = port;
  } :: s.server_notifications

let rec get_end_liste lst size =
  match lst with
      [] -> [] 
    | hd :: tail ->(if size = 0 then
	               tail
                     else 
		       get_end_liste tail (size-1);)

let rec get_begin_liste lst size =
  match lst with
      [] -> [] 
    | hd :: tail ->(if size = 0 then
	               []
                     else 
		       hd :: get_end_liste tail (size-1);)



let get_notify_to_send lst nbr =
  let size = List.length lst in
    (if size < nbr then
      lst,size
    else
      (get_end_liste lst (size-nbr)),nbr;) 

module LN = M.LocateNotif
      
let rec filter lst notif =
  match lst with 
      [] -> {
	LN.add = notif.add;
	LN.source_ip = notif.source_ip;
	LN.source_port =  notif.source_port; 
      }:: []
    | hd::tl -> (if (notif.source_ip = hd.LN.source_ip) && (notif.source_port = hd.LN.source_port) && (notif.add <> hd.LN.add) then
		   tl
		 else
		   filter tl notif;)
	
let supp_ack_notifs lst nbr =
  let size = List.length lst in 
    if  size <= nbr then
      []
    else
      (get_begin_liste lst nbr) 
  


let send_notification s sock =
 try
  (*Printf.printf "BEGIN CONSTRUCTION OF NOTIF PACKET\n";*)
  let notifs,nbr = get_notify_to_send s.server_notifications 200 in
  let nb_diff_md4 = ref 0 in
  let msg = Hashtbl.create nbr in
    List.iter (fun notif ->
		 try
		   let md4_sources = Hashtbl.find msg notif.md4 in
		   let md4_sources = filter md4_sources notif in
		     Hashtbl.replace msg notif.md4 md4_sources
		 with _ ->
		   incr nb_diff_md4; 
		   Hashtbl.add msg notif.md4 [{
		     LN.add = notif.add;
		     LN.source_ip = notif.source_ip;
		     LN.source_port = notif.source_port;
		   }]
	      ) notifs;
    direct_group_send sock (LocateNotifReq {
			 LN.nb_notifs = !nb_diff_md4;
			 LN.notifs= msg;
		       });
    (*TEMPORAIRE*)
    s.server_notifications <- supp_ack_notifs s.server_notifications nbr
 with _ -> Printf.printf "CAN'T MAKE NOTIF PACKET\n" 
    

let send_notif s =
  match s.server_sock with
      Some sock -> 
	 send_notification s sock 
    | None -> 
	raise NoSocket


let get_server_id ()=
  let find = ref true in
    while !find do
      if Hashtbl.mem servers_by_id !server_counter then
	begin
          incr server_counter;
          if !server_counter > 2000 then 
             server_counter := 0; 
	end
      else
	find := false;
    done;
    !server_counter

let send_to server t =
  match server.server_sock with
      Some sock -> 
	direct_group_send sock t
    | None -> 
	raise NoSocket
 
let broadcast_to_group id t =
  Hashtbl.iter (fun server_id server ->
		  try
                    if id <> server_id then
		       send_to server t
		  with NoSocket ->
		    ()
	       ) servers_by_id



let reply_to_server_connection s =
  match s.server_sock with
    None -> (*Printf.printf "Can't reply server connection\n";*)
      ()
            
  | Some sock ->
       try 
       (*Printf.printf "Can reply server connection\n";*)
	 let id = get_server_id () in
	(*Printf.printf ("Nouvel identifiant %d") id;
	  print_newline();*)
	   s.server_id <- id;
	   Hashtbl.add servers_by_id id s;

      (*print clients_by_id;*)
      
      (*Printf.printf "SET ID"; print_newline ();*)
       (*Pervasives.flush Pervasives.stdout;*)
(* send ID back to client *)
	   direct_group_send sock  (M.ACKConnectReq (
				      let module AC = M.ACKConnect in
					{
					  AC.group_id = !group_id;
					  AC.server_master_id = !server_id;
					  AC.server_id = s.server_id;
					  AC.tags = [
					    { tag_name = "name"; tag_value = String !!server_name };
					    { tag_name = "description"; tag_value = String !!server_desc }
					  ];
					}));
           
	   
	   ServerLocate.get_local_sources s; 
	   
	   send_notification s sock; 
	   
	   
           (*Printf.printf "notif send, broadcast new server position\n";*)
	   
	   let module SN = M.ServerNotification in
	     broadcast_to_group s.server_id (ServerNotificationReq {
					       SN.group_id = !group_id;
					       SN.server_id = s.server_id;
					       SN.server_ip = s.server_ip;
					       SN.server_port = s.server_port;
					     }
					    ); 
	     
	     
       with _ -> 
             Printf.printf "what about a pun\n"
(* send some messages 
      List.iter (fun msg ->
          direct_server_send sock (M.MessageReq msg)) !!welcome_messages*)
      



let check_handler s port ok sock event = 
  if not !ok then
    match event with
      CAN_REFILL 
    | BASIC_EVENT CAN_WRITE ->
        ok := true;
        TcpBufferedSocket.close sock "connect ok";
        (*Printf.printf "CAN WRITE\n";*)
        (*(match s.server_sock with
         None -> ()
        | Some sock -> Printf.printf "Cool\n");*)
        reply_to_server_connection s 
    | _ ->
        TcpBufferedSocket.close sock "can't connect";
        ok := false;
        Printf.printf "ERROR IN CONNECT\n"
    
let check_server s port =
  let try_sock = TcpBufferedSocket.connect "server to server"
      (Ip.to_inet_addr s.server_ip)
    port 
      (check_handler s port (ref false))
    (*server_msg_to_string*)
  in
  BasicSocket.set_wtimeout (TcpBufferedSocket.sock try_sock) 5.;
  (*Printf.printf "Checking sevrer ID\n";*)
  ()

let server_handler s sock event = 
  match event with
    BASIC_EVENT (CLOSED _) ->
    Printf.printf "%s:%d CLOSED received by server"
(Ip.to_string s.server_ip) s.server_port; print_newline ();
 
      (*connection_failed (s.server_connection_control);*)
      Printf.printf "server_handler call for close\n";
      s.server_sock <- None
      (*set_server_state s NotConnected;*)
      (*!server_is_disconnected_hook s*)
  | _ -> ()


let remove_server_locate s =
  Hashtbl.iter (fun remote_id local_id -> 
		  let c = Hashtbl.find clients_by_id local_id in
                      match c with
                      RemoteClient c -> 
                      (match c.remote_client_kind with
                       Firewalled_client ->
		         List.iter ( fun md4 ->
				     ServerLocate.supp md4 {loc_ip = c.remote_client_local_id; loc_port= 0;loc_expired=0.} 
				) c.remote_client_files
                      | KnownLocation (ip,port) ->
                          List.iter ( fun md4 ->
				     ServerLocate.supp md4 {loc_ip = ip; loc_port= port;loc_expired=0.} 
				) c.remote_client_files);           
		      Hashtbl.remove clients_by_id local_id
                      | _ -> ()
	       ) s.server_clients
    
    

let rec remove id lst =
  match lst with 
      [] -> []
    | hd :: tl -> if hd.server_id = id then
		     begin
		       remove_server_locate hd;
		       tl
		     end
		   else
		     remove id tl

 let remove_server s_id =
  try
    let s = Hashtbl.find servers_by_id s_id in
      remove_server_locate s;
      (match s.server_sock with
	   Some sock ->
	     close sock "Removed of the group";
	     s.server_sock <- None
	 | _ -> ());
      Hashtbl.remove servers_by_id  s_id
  with _ -> 
    to_connect := remove s_id !to_connect;
    decr nconnected_servers
 

 let print_servers () =
   Printf.printf "Contenu de server_by_id:\n";
   Hashtbl.iter (fun id s -> 
		   Printf.printf "server %d " id )
     servers_by_id;
   print_newline();
   Printf.printf "Contenu de to_connect:\n";
   List.iter (fun s -> 
		Printf.printf "server %d " s.server_id )
     !to_connect;
   print_newline()  


   

let server_disconnect_of_master s sock msg =
  Printf.printf "DISCONNECT:server %d disconnect_of_master call for close\n" s.server_id;
  s.server_sock <- None;
  close sock "connection dead";
  try
    let serv =  Hashtbl.find servers_by_id s.server_id in
      Hashtbl.remove servers_by_id s.server_id;
      to_connect := s :: !to_connect;
      print_servers()
  with _ -> Printf.printf "BIG PB IN DECONNECT\n";
    print_servers()
 

let server_disconnect s sock msg =
  Printf.printf "DISCONNECT:server %d disconnect call for close\n" s.server_id;
  s.server_sock <- None;
  close sock "connection dead";
  Hashtbl.remove servers_by_id s.server_id;
  to_connect := s :: !to_connect;    
  ()
 


(* let send_to server t =
  match server.server_sock with
      Some sock -> 
	direct_group_send sock t
    | None -> 
	raise NoSocket
 
let broadcast_to_group t =
  Hashtbl.iter (fun server_id server ->
		  try
		    send_to server t
		  with NoSocket ->
		    ()
	       ) servers_by_id*)


let server_to_server s t sock = 
  Printf.printf "----------------\nMSG received in server_to_server from %d locate at %s:%d\n" s.server_id (Ip.to_string s.server_ip) s.server_port; 
  M.print t;
  match t with
      M.ServerConnectReq t ->
	if !!relais_master then
	  let module SC =  M.ServerConnect in 
	    if ((t.SC.max_clients + !ngroup_clients) > !!max_group_clients or (t.SC.max_files + !ngroup_files) > !!max_group_files) then
	      begin 
		(*new server allowed to much files or clients for the goupe*)
		Hashtbl.remove  servers_by_id s.server_id;
		TcpBufferedSocket.close sock "CONNECTION REFUSED: to much file or client on your server";
		decr nconnected_servers
	      end
	    else
	      begin
		(*server accepted*)
		s.server_md4 <- t.M.ServerConnect.md4;
		s.server_port <- t.M.ServerConnect.port;
		s.server_tags <- t.M.ServerConnect.tags;
	
		check_server s s.server_port;      
	      end;
	else
	  begin
	    Hashtbl.remove  servers_by_id s.server_id;
	    TcpBufferedSocket.close sock "CONNECTION REFUSED: I'm not a master server";
	    decr nconnected_servers
	  end
	      

    | M.ACKConnectReq t ->
	let module A = M.ACKConnect in
	  s.server_group_id <- t.A.group_id;
	  s.server_master <- true ;
	  s.server_id <- t.A.server_master_id;
	  s.server_tags <- t.A.tags;
	

	  group_id := t.A.group_id;
	  server_id := t.A.server_id;
          
	  (*Hashtbl.add servers_by_id s.server_id s;*)

	  ServerLocate.get_local_sources s;

	  Printf.printf "Server connect to %s\n" (Md4.to_string t.A.group_id);

          (*send_notification s sock;*) 

	  ()
	  
    | M.ServerNotificationReq t ->
	if !!relais_master then
	  (*"I'm the law and ServerNotificationReq messages isn't for me"*)
	  ()
	else
	  (*new server in the group*)
	  if s.server_master then
	    begin
	      
              let module SN = ServerNotification in
	      let new_server = {
		server_group_id = t.SN.group_id;
		server_master = false ;
		server_id = t.SN.server_id;
		server_md4 = Md4.null;
		server_ip =  t.SN.server_ip;
		server_port =  t.SN.server_port;
		server_sock = None;
		server_need_recovery = false;
		server_notifications = [];
		server_clients = Hashtbl.create 100;
		server_tags = [];
	      } in
		
		to_connect := new_server :: !to_connect;
		
		(*Hashtbl.add servers_by_id new_server.server_id new_server;*)
		
		(*connect to the new server*)
		(*connect_server new_server;*)
  
		(*put all local information in the buffer*)
	
                Printf.printf "Server %s:%d join the group\n" (Ip.to_string new_server.server_ip) new_server.server_port; 
	
	    end
	
    | M.ConnectByGroupReq t ->
	let module CG = ConnectByGroup in
	  if (List.exists (fun s -> if s.server_id = t.CG.server_id then true else false) !to_connect) then
	    begin
	      Printf.printf "Reconnection from %d\n" t.CG.server_id;
	    end
	  else
	    begin
	      if (Hashtbl.mem servers_by_id t.CG.server_id) then 
		Printf.printf "ATTENTION PB in Reconnection %d\n" t.CG.server_id
	      else
	    
	      Printf.printf "Connection from %d server in %s group\n" t.CG.server_id (Md4.to_string t.CG.group_id);
	      s.server_group_id <- t.CG.group_id;
	      s.server_id <- t.CG.server_id;
	      s.server_ip <- t.CG.server_ip;
	      s.server_port <- t.CG.server_port; 
              Hashtbl.add servers_by_id s.server_id s;
	    end;
	  ()
	 
	  

    
    | M.RecoveryReq t ->	
	remove_server_locate s;
	()

    | M.ServerSuppReq t ->
	if !!relais_master then
	  (*"I'm the law and ServerNotificationReq messages isn't for me"*)
	  ()
	else 
	  begin
	    if s.server_master then
		try 
		  let module SS = M.ServerSupp in
		    remove_server t.SS.server_id;
		with _ -> ()
	  end
   
  

    | LocateNotifReq t ->
	let module LN = M.LocateNotif in 
	  Hashtbl.iter ( fun md4 sources_list -> 
			   (*ServerLocate.notifications md4 sources_list;*)
			    List.iter ( fun source ->
				       try
					 begin
					   (*modify client's list of md4 shared*)
					   let local_id = Hashtbl.find s.server_clients source.LN.source_ip in 
					   let client = Hashtbl.find clients_by_id local_id in
                                           match client with
                                            RemoteClient client ->
                                             (match client.remote_client_kind with
                                                Firewalled_client ->
                                                  source.LN.source_ip <- local_id
                                             | _ -> ();
					     if source.LN.add then
					       (* if the notification is a add*)
					       client.remote_client_files <- md4 :: client.remote_client_files
					     else
					       (* if the notification is a supp*)
					       begin
						 client.remote_client_files <- List.filter (fun x ->
										       md4 <> x 
										    )  client.remote_client_files;
						 if client.remote_client_files = [] then
						   begin
						     Hashtbl.remove s.server_clients source.LN.source_ip;
						     Hashtbl.remove clients_by_id local_id 
						   end
					       end)
                                             | _ -> () 
					 end
				     with _ -> 
				       (*if remote client is not in server's client list*)
				       let new_id = get_client_id source.LN.source_ip in
					 Hashtbl.add s.server_clients source.LN.source_ip new_id;
					 let c = {
					   remote_client_local_id = new_id; 
					   remote_client_server = s.server_id;
					   remote_client_md4 = Md4.null;
					   remote_client_kind = ( if source.LN.source_port = 0 then
							     Firewalled_client
							   else
							     KnownLocation (source.LN.source_ip,source.LN.source_port)
							 );
					   remote_client_files = [md4];
					 } in
                                         Hashtbl.add clients_by_id new_id (RemoteClient c);
                                         match c.remote_client_kind with
                                                Firewalled_client ->
                                                   source.LN.source_ip <- new_id
                                             | _ -> ()
				      ) sources_list;
                             ServerLocate.notifications md4 sources_list
		       ) t.LN.notifs
	  
	
    | MessageReq t ->
	if s.server_master then
	  Printf.printf "From Server Master:\n"
	else
	  Printf.printf "From Basic Server %d :\n" s.server_id;
	M.Message.print t


  
    | QuitReq ->
	close sock "Removed of the group";
	remove_server s.server_id;
	let module SS = ServerSupp in
	  broadcast_to_group s.server_id (ServerSuppReq {
				SS.group_id = !group_id;
				SS.server_id = s.server_id;
			      }
			     )
	  

    | _ -> Printf.printf "Unknown TCP requete in server_group from %d\n" s.server_id;
           ();
    print_newline() 
   
exception CantConnect
     
let connect_server s = 
  try
    Printf.printf "CONNECTING TO ONE SERVER %s:%d\n" (Ip.to_string s.server_ip) (s.server_port+5) ; 
    (*connection_try s.server_connection_control;*)
    incr nconnected_servers; 
    let sock = TcpBufferedSocket.connect 
          "server to server"
        (Ip.to_inet_addr s.server_ip) (s.server_port+5) 
          (server_handler s) (* Mftp_comm.server_msg_to_string*)  in
      (*set_server_state s Connecting;*)
      (*set_read_controler sock download_control;
      set_write_controler sock upload_control;*)
      
      set_reader sock (Mftp_comm.cut_messages ServerMessages.parse
          (server_to_server s));
      if !!relais_master then
        set_closer sock (server_disconnect_of_master s) 
      else
	set_closer sock (server_disconnect s);
      set_rtimeout sock 60.;
      set_handler sock (BASIC_EVENT RTIMEOUT) (fun s ->
						 Printf.printf "Standart rtimeout";
						 close s "timeout"  
					      );
      
      
      s.server_sock <- Some sock;


    with _ -> 
      Printf.printf "%s:%d IMMEDIAT DISCONNECT\n"
      (Ip.to_string s.server_ip) s.server_port;
(*      Printf.printf "DISCONNECTED IMMEDIATLY"; print_newline (); *)
        decr nconnected_servers;
        s.server_sock <- None;
	raise CantConnect
        (*set_server_state s NotConnected;*)
        (*connection_failed s.server_connection_control*)

let join_a_group ip port =

  let server = {
    server_group_id = Md4.null;
    server_master = false ;
    server_id = 0;
    server_md4 = Md4.null;
    server_ip = ip;
    server_port =  port;
    server_sock = None;
    server_need_recovery = false;
    server_notifications = [];
    server_clients = Hashtbl.create 100;
    server_tags = [];
  } in
    
    try
      connect_server server;
    
      Hashtbl.add servers_by_id server.server_id server;
      
      send_to server (ServerConnectReq 
			(let module CS = M.ServerConnect in
			   {
			     CS.md4 = !!server_md4;
			     CS.ip = !!server_ip;
			     CS.port = !!server_port;
			     CS.max_clients = !!max_group_clients;
			     CS.max_files = !!max_group_files;
			     CS.tags =  [
			       { tag_name = "name"; tag_value = String !!server_name };
			       { tag_name = "description"; tag_value = String !!server_desc }
			     ];
			   })
		     )
	
    with _->
      Printf.printf "Can't open socket to %s:%d" (Ip.to_string ip) port
      (*Hashtbl.remove servers_by_id 0*)

let connect_a_group () = 
 List.iter (fun (ip,port) -> 
           join_a_group ip port
)!!known_master
   
   

  
let handler t event =
  (*Printf.printf "CONNECTION"; print_newline ();*)
  match event with
    TcpServerSocket.CONNECTION (s, Unix.ADDR_INET (from_ip, from_port)) ->

      if !!max_servers <= !nconnected_servers then
	  (*Printf.printf "too much clients\n";*)
          Unix.close s
      else
      let sock = TcpBufferedSocket.create "server server connection" s (fun _ _ -> ()) 
        (*server_msg_to_string*)
        in
      
      let ip = Ip.of_inet_addr from_ip in
      let server = {
	server_group_id = Md4.null;
	server_master = false;
        server_id = 0;
	server_md4 = Md4.null;
        server_ip = ip;
	server_port = from_port;
	server_need_recovery = false;
        server_sock = Some sock;
	server_notifications = [];
	server_clients = Hashtbl.create 100; 
        server_tags = []; 
        } in

      incr nconnected_servers;

      TcpBufferedSocket.set_reader sock (
        Mftp_comm.cut_messages ServerMessages.parse (server_to_server server));
      if !!relais_master then
        TcpBufferedSocket.set_closer sock 
          (server_disconnect_of_master server)
      else
	TcpBufferedSocket.set_closer sock 
          (server_disconnect server);
  | _ -> 
      Printf.printf "???"; print_newline ();
      ()  

(*****************TODO******)    
let get_ride_of s =
  false

let get_local_sources s =
  List.iter ( fun c_id ->
		let c = Hashtbl.find clients_by_id c_id in
                match c with 
                LocalClient c ->
		  (match c.client_kind with
		      Firewalled_client ->
			List.iter ( fun md4 ->
				      s.server_notifications <- {
					add = true;
					md4 = md4;
					source_ip = c_id; 
					source_port = 0;
				      } :: s.server_notifications
				  ) c.client_files
		    | KnownLocation (ip,port) ->
			List.iter ( fun md4 ->
				      s.server_notifications <- {
					add = true;
					md4 = md4;
					source_ip =  ip;
					source_port = port;
				      } :: s.server_notifications
				  ) c.client_files)
                  | _ -> ()
	    )!local_clients

let action_notify_servers time =
  Printf.printf "+++++++++++++++\nNotify Location Process\n"; 
  Hashtbl.iter (fun id s ->
		  Printf.printf "Send Notif to %d\n" id; 
		  match s.server_sock with
		      None -> Printf.printf "CAN'T NOTIF CAUSE NO SOCKET";
		    | Some sock -> 
			if s.server_need_recovery then
			  begin 
			    ServerLocate.get_local_sources s;
			    let module R = M.Recovery in
			      send_to s (RecoveryReq 
					   {
					     R.group_id = !group_id;
					     R.server_id = !server_id;
					     R.server_ip = !!server_ip;
					     R.server_port = !!server_port;
					   });
			      s.server_need_recovery <- false;
			  end;
                        Printf.printf "Server send notif to server %d \n" id;
			send_notification s sock
	       ) servers_by_id
    
    
let action_connect_servers time =
  Printf.printf "+++++++++++++++\nConnection Process\n"; 
  let unconnect = ref [] in
    List.iter (fun s ->
		 try
		   Printf.printf "->Try to connect to %d %s:%d\n" s.server_id (Ip.to_string s.server_ip) s.server_port; 
		   connect_server s;
		   if !!relais_master then
		   (match s.server_sock with 
			Some sock ->
			  Printf.printf "Wait for connection";
			  let f =  (fun s sock ->
				      Printf.printf "My Rtimeout work\n";
				      close sock "timeout";
				      Hashtbl.remove servers_by_id s.server_id
			       ) in
			    set_handler sock (BASIC_EVENT RTIMEOUT) (f s);
			    set_rtimeout sock 0.;
		      | None -> raise NoSocket); 
		   let module CG = ConnectByGroup in
		     send_to s (ConnectByGroupReq 
				  {
				    CG.group_id = !group_id; 
				    CG.server_id = !server_id;
				    CG.server_ip = !!server_ip;
				    CG.server_port = !!server_port; 
				  });
		     Printf.printf "PB add to hash\n"; 
		     Hashtbl.add servers_by_id s.server_id s;
		 with _ ->
		   Printf.printf "CAN'T RECONNECT TO SERVER %d %s:%d\n" s.server_id (Ip.to_string s.server_ip) s.server_port;
		   if !!relais_master then
		     begin
		       Printf.printf "Server supprimer du groupe\n";
		       let module SS = ServerSupp in
			 broadcast_to_group !server_id (ServerSuppReq 
							  {
							    SS.group_id = !group_id;
							    SS.server_id = s.server_id
							  }
						       )
		     end
		   else
		     unconnect := s :: !unconnect;
	      ) !to_connect;
    Printf.printf "Fin du protocole de reconnection";
    to_connect := !unconnect;
    print_servers()

      
      
let bprint_clients_info buf option =
 Hashtbl.iter (fun id c ->
      match c with
      LocalClient c ->
        begin
           Printf.bprintf buf "LocalClient: %s\n" (Ip.to_string id);
           match option with
           _ -> ()
        end
      | RemoteClient c ->
        begin 
           Printf.bprintf buf "RemoteClient: %s\n" (Ip.to_string id);
            match option with
           _ -> ()
	end
	) clients_by_id
		    

let bprint_server_info buf option =
  Hashtbl.iter (fun id s ->
		    Printf.bprintf buf "Server %d\n" id;
		    ) servers_by_id
			