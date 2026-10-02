const base=Get("DB5KM",{depth:0});
const C={ink:"#141735",muted:"#686D82",purple:"#5938D6",line:"#E7E7EE",bg:"#F7F7FA",green:"#18765C",red:"#B43C48"};
const frame=(p,name,props={})=>Insert(p,{type:"frame",name,layout:"vertical",height:"fit_content",width:"fill_container",gap:12,...props});
const text=(p,name,content,size=14,color=C.ink,weight="400")=>Insert(p,{type:"text",name,content,textGrowth:"fixed-width",width:"fill_container",fontFamily:"Inter",fontSize:size,fontWeight:weight,lineHeight:1.5,fill:color});
const icon=(p,name,glyph,color=C.muted,size=20)=>Insert(p,{type:"icon",name,library:"lucide",icon:glyph,width:size,height:size,fill:color});
const row=(p,name,props={})=>frame(p,name,{layout:"horizontal",alignItems:"center",...props});
const action=(p,label)=>Insert(p,{type:"ref",name:label,ref:"ZvnIy",width:"fill_container",descendants:{"FJVze":{content:label}}});
const nav=(p,selected)=>{
 const n=row(p,"Bottom navigation",{padding:[12,8,18,8],fill:"#FFFFFF",gap:0});
 for(const [i,label,glyph]of[[0,"Ringkasan","layout-dashboard"],[1,"Armada","car"],[2,"Peringatan","bell"],[3,"Analisis","chart-no-axes-combined"],[4,"Operasi","calendar-days"]]){
  const item=frame(n,label,{alignItems:"center",gap:6});icon(item,label+" icon",glyph,i===selected?C.purple:C.muted);const t=text(item,label+" label",label,10,i===selected?C.purple:C.muted,i===selected?"600":"400");Update(t,{textAlign:"center"});
 }
};
const phone=(title,i,x)=>{
 const s=Insert(document,{type:"frame",name:"RevTrack / "+title,x,y:base.y+760,width:390,height:"fit_content(844)",layout:"vertical",fill:C.bg,clip:true,placeholder:true,cornerRadius:24});
 const status=row(s,"System status bar",{height:48,padding:[12,24],justifyContent:"space_between"});text(status,"Clock","9:41",14,C.ink,"600");icon(status,"Battery","battery-full",C.ink);
 const header=row(s,"App header",{height:56,padding:[8,20],fill:"#FFFFFF"});text(header,"Wordmark","RevTrack",22,C.ink,"700");icon(header,"Refresh","refresh-cw");
 const content=frame(s,"Content",{padding:20,gap:20});text(content,"Workspace","Rev Rental · Jakarta",12,C.muted);text(content,"Page title",title,26,C.ink,"700");return{s,content,index:i};
};
workflows=[];
const alerts=phone("Peringatan",2,base.x+1410);workflows.push(alerts.s);
text(alerts.content,"Open alerts count","3 peringatan perlu ditinjau.",14,C.muted);
text(alerts.content,"Review guidance","Periksa catatan kejadian sebelum menandai peringatan sebagai ditinjau.",13,C.muted);
for(const[title,plate,body,severity]of[["Koneksi kendaraan terputus","B 6618 REV","Laporan terakhir belum diperbarui. Periksa perangkat dan hubungi pengemudi.","Koneksi"],["Baterai di bawah 30%","B 3019 REV","Sisa baterai 26%. Periksa kebutuhan perjalanan sebelum mengisi ulang.","Energi"],["Perjalanan perlu diperiksa","B 2086 REV","Buka catatan kejadian untuk memeriksa posisi dan aktivitas kendaraan.","Perjalanan"]]){
 const card=frame(alerts.content,title,{padding:18,fill:"#FFFFFF",cornerRadius:16});const top=row(card,"Alert header");icon(top,"Alert symbol","circle-alert","#966016",22);text(top,"Title",title,16,C.ink,"600");text(card,"Plate and category",plate+" · "+severity,12,C.muted);text(card,"Description",body,13,C.muted);action(card,"Tandai ditinjau");
}
text(alerts.content,"Demo disclosure","Kejadian pada mode demo merupakan simulasi.",11,C.muted);nav(alerts.s,2);Update(alerts.s,{placeholder:false});
const analysis=phone("Analisis armada",3,base.x+1880);workflows.push(analysis.s);
text(analysis.content,"Analysis subtitle","Ringkasan koneksi, energi, dan penugasan kendaraan.",14,C.muted);
const input=row(analysis.content,"Search analysis topics",{padding:14,fill:"#FFFFFF",cornerRadius:12});icon(input,"Search","search");text(input,"Search hint","Cari topik analisis",14,C.muted);
text(analysis.content,"Topic selector","Koneksi       Energi       Pengemudi",14,C.purple,"600");
const report=frame(analysis.content,"Connection summary",{padding:20,fill:"#FFFFFF",cornerRadius:16,gap:18});text(report,"Summary title","Koneksi kendaraan",18,C.ink,"600");text(report,"Summary body","1 kendaraan sedang offline. Periksa laporan terakhir dan hubungi pengemudinya bila perlu.",14,C.muted);text(report,"Offline vehicle","B 6618 REV · Offline",14,C.red,"600");action(report,"Tinjau peringatan");text(analysis.content,"Analysis provenance","Ringkasan dihitung dari data armada dengan aturan sederhana. Data mode demo merupakan simulasi.",12,C.muted);nav(analysis.s,3);Update(analysis.s,{placeholder:false});
const operations=phone("Operasi",4,base.x+2350);workflows.push(operations.s);
text(operations.content,"Operations subtitle","Kelola rental, jadwal servis, dan catatan aktivitas.",14,C.muted);text(operations.content,"Operations tabs","Rental       Servis       Audit       Laporan",13,C.purple,"600");
const empty=frame(operations.content,"No bookings state",{padding:24,fill:"#FFFFFF",cornerRadius:16,gap:18});icon(empty,"Booking icon","calendar-days",C.purple,32);text(empty,"Empty title","Belum ada booking",20,C.ink,"600");text(empty,"Empty explanation","Tambahkan jadwal rental untuk kendaraan dan pelanggan. Jadwal yang bentrok akan ditandai sebelum disimpan.",14,C.muted);action(empty,"Booking baru");
text(operations.content,"Audit note","Booking, pengembalian, dan servis tercatat dalam riwayat aktivitas.",12,C.muted);nav(operations.s,4);Update(operations.s,{placeholder:false});
const states=Insert(document,{type:"frame",name:"RevTrack / Interaction states",x:base.x+1900,y:base.y,width:1050,height:"fit_content",layout:"vertical",padding:40,gap:24,fill:"#FFFFFF",placeholder:true});
text(states,"States heading","Respons setiap tindakan",28,C.ink,"700");text(states,"State timing","180–240 ms untuk perpindahan · shimmer hanya saat menunggu · gerakan mengikuti pengaturan perangkat",14,C.muted);
const buttons=row(states,"Action states",{gap:16});
for(const[name,glyph,bg,color]of[["Siap","arrow-right",C.purple,"#FFFFFF"],["Menyimpan…","loader-circle","#F0ECFC",C.purple],["Tersimpan","circle-check","#EDF7F2",C.green],["Coba lagi","rotate-cw","#FFF0F1",C.red]]){
 const b=row(buttons,name,{height:48,padding:[12,16],fill:bg,cornerRadius:12,reusable:true});icon(b,name+" icon",glyph,color,18);text(b,name+" label",name,14,color,"600");
}
const confirmations=row(states,"Outcome patterns",{gap:24});
for(const[title,body,glyph,color]of[["Tersimpan","Konfirmasi muncul setelah layanan menerima perubahan.","circle-check",C.green],["Hapus item ini?","Jelaskan item yang dihapus, sediakan Batal, dan tampilkan hasil setelah berhasil.","trash-2",C.red]]){
 const c=frame(confirmations,title,{padding:24,fill:C.bg,cornerRadius:16});icon(c,title+" symbol",glyph,color,28);text(c,title+" heading",title,18,C.ink,"600");text(c,title+" copy",body,14,C.muted);
}
text(states,"Deletion availability","Pola hapus untuk komponen mendatang. Aksi hapus belum tersedia pada layanan RevTrack saat ini.",12,C.muted);Update(states,{placeholder:false});
Print({workflows,states});
