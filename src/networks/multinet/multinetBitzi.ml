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

open Printf2
open Options
open BasicSocket
open TcpBufferedSocket
open Md4
  
open CommonClient
open CommonComplexOptions
open CommonTypes
open CommonFile
open CommonGlobals
open CommonOptions

open MultinetTypes
open MultinetGlobals

(* 
  
To find equivalent UIDs on different networks, we can use www.bitzi.com:

http://ticket.bitzi.com/rdf/BCLD3DINKJJRGYGHIYAX7HG5HXSM3XNH.E4IHTEMZIJE4NBCWSBZ6TIWQTDGYYXVPGIRJ5KQ
http://ticket.bitzi.com/rdf/urn:sha1:BCLD3DINKJJRGYGHIYAX7HG5HXSM3XNH 
  
  # let t = Xml.parse_file "xml1";;
val t : Xml.xml =
  Xml.XML ("rdf:RDF",
   [("xmlns:rdf", "http://www.w3.org/1999/02/22-rdf-syntax-ns#");
    ("xmlns:rdfs", "http://www.w3.org/2000/01/rdf-schema#");
    ("xmlns:dc", "http://purl.org/dc/elements/1.1/");
    ("xmlns:bz", "http://bitzi.com/xmlns/2002/01/bz-core#");
    ("xmlns:mm", "http://musicbrainz.org/mm/mm-2.0#")],
   [Xml.XML ("bz:Authentication", [], []);
    Xml.XML ("rdf:Description",
     [("rdf:about", "urn:sha1:BCLD3DINKJJRGYGHIYAX7HG5HXSM3XNH");
      ("bz:ticketMinted", "2003-06-08 22:15:33 GMT");
      ("bz:ticketExpires", "2003-06-09 22:15:33 GMT");
      ("bz:ticketFirstCreated", "2001-07-15 23:48:07 GMT");
      ("bz:ticketFilename",
      "BCLD3DINKJJRGYGHIYAX7HG5HXSM3XNH-200306092215.bztk");
      ("bz:ticketRequestsDay", "14"); ("bz:ticketOutboundClicksDay", "0");
      ("bz:fileGoodness", "2.2"); ("bz:fileJudgement", "Best Version");
      ("dc:format", "audio/mp3"); ("bz:fileLength", "4577608");
("bz:fileFirst20Bytes", "4944330200000000006E54543200000F00546865");

  
("bz:fileMD5", "NTUHNJDIJH6IDHQ5GPOSUFVSCM");
("bz:fileUUHash", "mcR96OHbEJLjxV4eudW9YDMW8q4");
("bz:fileED2kHash", "83d6c3bef2732d310bd9105e850c7864");

  
      ("mm:duration", "286743"); ("bz:audioBitrate", "128");
      ("bz:audioSamplerate", "44100"); ("bz:audioChannels", "1");
      ("bz:audioSha1", "LQAIDHEMU43QFN5JNYFAVFEYZI3TOZ6L")],
     [Xml.XML ("dc:description",
       [("dc:title", "The Bjork Song");
        ("dc:creator", "The Brunching Shuttlecocks");
        ("bz:albumName", "www.brunching.com"); ("mm:trackNum", "1");
        ("dc:date", "2000")],
       []);
      Xml.XML ("bz:fileName",
       [("dc:title", "Brunching Shuttlecocks - Bjorksong.mp3")], []);
      Xml.XML ("bz:fileName", [("dc:title", "bjorksong.mp3")], []);
      Xml.XML ("bz:sponsor",
       [("rdf:resource",
        "http://bitzi.com/r/s?u=http%3A%2F%2Fwww.cafeshops.com%2Fcp%2Fstore.aspx%3Fs%3Dbitzi&#38;v=0&#38;x=NDZ7243XSSFBHLWUVDCCRGJ3UA7CWDREHE2DINZVGUQDCMRYEAYCAMBAGA");
        ("dc:title", "New: Bitzi Logo Stuff");
        ("bz:sponsorText1", "T-shirts, hats, bags, and more ");
        ("bz:sponsorText2", "Support Bitzi -- show us your bits!");
        ("bz:sponsorSite", "www.cafeshops.com"); ("bz:sponsorRank", "1");
        ("bz:sponsorClickCost", "affiliate")],
       [])])])

  *)

let make_request url = 
  
  let module H = Http_client in
  let r = {
      H.basic_request with
      
      H.req_url = Url.of_string url;
      H.req_user_agent = "Mozilla/5.0 (Linux 2.4.19-16mdk i686; U) Opera 6.11  [en]";
      H.req_referer = None;
      H.req_request = H.GET;
    } in
  
  r

let progress _ _ = ()

let parse_bitzi_ticket file s =
  lprintf "Bitzi ticket downloaded:%s\n" (String.escaped s);
  let xml = Xml.parse_string s in
  file.file_bitzi_ticket <- Bitzi_ticket s;
  let Xml.XML (_,_, list) = xml in
  List.iter (fun (Xml.XML (header, args, _)) ->
      match header with
        "rdf:Description" -> 
(*                                 
("bz:fileMD5", "NTUHNJDIJH6IDHQ5GPOSUFVSCM");
("bz:fileUUHash", "mcR96OHbEJLjxV4eudW9YDMW8q4");
("bz:fileED2kHash", "83d6c3bef2732d310bd9105e850c7864");
*)
          List.iter (fun (field, value) ->
              match field with
              | "bz:fileMD5" -> ()
              | "bz:fileUUHash" ->
                  let md5ext = Md5Ext.of_string ("=" ^ value ^ "=") in
                  add_uids file [Md5Ext ("", md5ext)]
              | "bz:fileED2kHash" ->
                  let md4 = Md4.of_string value in
                  add_uids file [Ed2k ("", md4)]
              
              | _ -> ()
          ) args;
          List.iter (fun f -> 
              try f.op_download_start file 
              with _ -> ()) !networks;                            
      | _ -> ()
  ) list

(*
>  http://bitzi.com/lookup/OILFTPP7BIHSFNQHEAJ3GZOTSBOCN57P
>  http://bitzi.com/lookup/ed2k:0dfdf429ecec79510d9baf9f517d5ece
>  http://bitzi.com/lookup/sig2dat:egOkYJlkawkKLl9vtqPGB44HL5M
*)

let parse_possible_bitzi_ticket sha1 file s =
  lprintf "****** parse_possible_bitzi_ticket *******\n";
  lprintf "Bitzi ticket downloaded:%s\n" (String.escaped s);
  let xml = Xml.parse_string s in
  file.file_bitzi_ticket <- Bitzi_ticket s;
  let Xml.XML (_,_, list) = xml in
  let found_uids = ref [uid_of_uid (Sha1 ("", sha1))] in
  let found_file_size = ref zero in
  List.iter (fun (Xml.XML (header, args, _)) ->
      match header with
        "rdf:Description" -> 
(*                                 
("bz:fileMD5", "NTUHNJDIJH6IDHQ5GPOSUFVSCM");
("bz:fileUUHash", "mcR96OHbEJLjxV4eudW9YDMW8q4");
("bz:fileED2kHash", "83d6c3bef2732d310bd9105e850c7864");
*)
          List.iter (fun (field, value) ->
              match field with
              | "bz:fileMD5" -> ()
              | "bz:fileUUHash" ->
                  let md5ext = Md5Ext.of_string ("=" ^ value ^ "=") in
                  found_uids := (uid_of_uid (Md5Ext ("", md5ext))) :: !found_uids
              | "bz:fileED2kHash" ->
                  let md4 = Md4.of_string value in
                  found_uids := (uid_of_uid (Ed2k ("", md4))) :: !found_uids
              | "bz:fileLength" ->
                  found_file_size := Int64.of_string value
              | _ -> ()
          ) args;
      | _ -> ()
  ) list;
  if !found_file_size = file_size file then
    List.iter (fun uid ->
        if List.mem uid file.file_uids then begin
(* One of the uids found match the file, it's our file ! *)
            lprintf "********** possible bitzi ticket match file\n";
            add_uids file !found_uids;
            List.iter (fun f -> 
                try f.op_download_start file 
                with _ -> ()) !networks;                            
          
          end
    ) !found_uids

let request_possible_bitzi_ticket file sha1 =
  lprintf "***** request_possible_bitzi_ticket *****\n";
  Http_client.wget_string 
    (make_request
      (Printf.sprintf "http://ticket.bitzi.com/rdf/urn:sha1:%s"
        (Sha1.to_string sha1))) 
  (parse_possible_bitzi_ticket sha1 file) progress

let parse_bitzi_lookup file s = 
  lprintf "******* parse_bitzi_lookup *******\n%s\n"
    (String.escaped s);
  let rec iter pos =
    let pos = (String2.search_from s pos "urn:sha1:")+9 in
    let sha1 = String.sub s pos 32 in
    lprintf "******** urn:sha1:%s found *********\n" sha1;
    let sha1 = Sha1.of_string sha1 in
    request_possible_bitzi_ticket file sha1;
    iter pos
  in
  try
    iter 0
  with _ -> ()

let query_bitzi_ticket file =
  match file.file_bitzi_ticket with
    Bitzi_ticket xml -> ()
  | Bitzi_not_found -> ()
  | Bitzi_next_retry time ->
      if last_time () > time then begin
          file.file_bitzi_ticket <- Bitzi_next_retry (last_time () + 600);
          List.iter (fun uid ->
              match uid with
                Sha1 (_, sha1) ->
                  
                  lprintf "Retrieve bitzi ticket\n";
                  file.file_bitzi_ticket <- Bitzi_not_found;
                  Http_client.wget_string 
                    (make_request
                      (Printf.sprintf "http://ticket.bitzi.com/rdf/urn:sha1:%s"
                        (Sha1.to_string sha1))) 
                  (parse_bitzi_ticket file) progress
              | _ -> ()
          ) file.file_uids;
          match file.file_bitzi_ticket with
            Bitzi_next_retry _ ->
(* No Sha1 uid: try the ed2k or sig2dat uids  *)
              List.iter (fun uid ->
                  match uid with
                    Ed2k (_, ed2k) ->
                      
                      lprintf "********** Retrieve bitzi lookup by ed2k\n";
                      Http_client.wget_string 
                        (make_request
                          (Printf.sprintf "http://bitzi.com/lookup/ed2k:%s" (Md4.to_string ed2k)))
                      (parse_bitzi_lookup file) progress
                  | Md5Ext (_, md5ext) ->
                      
                      lprintf "********** Retrieve bitzi lookup by sig2dat\n";
                      let md5ext = Md5Ext.to_string md5ext in
                      let len = String.length md5ext in
                      Http_client.wget_string 
                        (make_request
                          (Printf.sprintf "http://bitzi.com/lookup/sig2dat:%s" (String.sub md5ext 1 (len -2))))
                      (parse_bitzi_lookup file) progress
                  | _ -> ()
              ) file.file_uids;
          
          
          | _ -> ()
        end

let minute_timer _ =
  List.iter (fun file ->
      query_bitzi_ticket file) !current_files
  