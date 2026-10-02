const base = Get("DB5KM",{depth:0});
const C = {ink:"#141735",muted:"#686D82",purple:"#5938D6",line:"#E7E7EE",bg:"#F7F7FA",green:"#18765C",red:"#B43C48"};
const frame = (p,name,props={}) => Insert(p,{type:"frame",name,layout:"vertical",height:"fit_content",width:"fill_container",gap:12,...props});
const text = (p,name,content,size=14,color=C.ink,weight="400") => Insert(p,{type:"text",name,content,textGrowth:"fixed-width",width:"fill_container",fontFamily:"Inter",fontSize:size,fontWeight:weight,lineHeight:1.4,fill:color});
const icon = (p,name,glyph,color=C.muted,size=20) => Insert(p,{type:"icon",name,library:"lucide",icon:glyph,width:size,height:size,fill:color});
const row = (p,name,props={}) => frame(p,name,{layout:"horizontal",alignItems:"center",...props});
const separator = p => Insert(p,{type:"rectangle",name:"Divider",width:"fill_container",height:1,fill:C.line});
button = Insert(document,{type:"frame",name:"RevTrack / Primary action",x:base.x,y:base.y+600,width:350,height:48,layout:"horizontal",alignItems:"center",justifyContent:"center",gap:10,padding:12,fill:C.purple,cornerRadius:12,reusable:true,placeholder:true});
icon(button,"Action icon","arrow-right","#FFFFFF",18);
buttonLabel = text(button,"Action label","Lihat armada",14,"#FFFFFF","600");
Update(buttonLabel,{textGrowth:"auto"});
Update(button,{placeholder:false});
const action = (p,label,tonal=false) => Insert(p,{type:"ref",name:label,ref:button,width:"fill_container",fill:tonal?"#F0ECFC":C.purple,descendants:{[buttonLabel]:{content:label,fill:tonal?C.purple:"#FFFFFF"},"Action icon":{fill:tonal?C.purple:"#FFFFFF"}}});
const nav = (p,selected) => {
 const n=row(p,"Bottom navigation",{padding:[12,8,18,8],fill:"#FFFFFF",gap:0});
 for(const [i,label,glyph] of [[0,"Ringkasan","layout-dashboard"],[1,"Armada","car"],[2,"Peringatan","bell"],[3,"Analisis","chart-no-axes-combined"],[4,"Operasi","calendar-days"]]){
  const item=frame(n,label,{width:"fill_container",alignItems:"center",gap:6});
  icon(item,label+" icon",glyph,i===selected?C.purple:C.muted,20);
  const t=text(item,label+" label",label,10,i===selected?C.purple:C.muted,i===selected?"600":"400");Update(t,{textAlign:"center"});
 }
};
const phone = (title,i,x) => {
 const s=Insert(document,{type:"frame",name:"RevTrack / "+title,x,y:base.y+760,width:390,height:"fit_content(844)",layout:"vertical",fill:C.bg,clip:true,placeholder:true,gap:0,cornerRadius:24});
 const status=row(s,"System status bar",{height:48,padding:[12,24],justifyContent:"space_between"});
 const clock=text(status,"Clock","9:41",14,C.ink,"600");Update(clock,{textGrowth:"auto"});
 const sys=row(status,"System icons",{width:"fit_content",gap:8});icon(sys,"Mobile signal","signal",C.ink,16);icon(sys,"Battery","battery-full",C.ink,20);
 const header=row(s,"App header",{height:56,padding:[8,20],fill:"#FFFFFF",justifyContent:"space_between"});
 text(header,"Wordmark","RevTrack",22,C.ink,"700");icon(header,"Refresh data","refresh-cw",C.muted,20);
 const content=frame(s,"Content",{padding:20,gap:20});
 text(content,"Workspace","Rev Rental · Jakarta",12,C.muted);
 text(content,"Page title",title,26,C.ink,"700");
 return {s,content,index:i};
};
const vehicle = (p,plate,name,status,energy) => {
 const r=row(p,plate+" vehicle",{padding:[16,0],gap:12});
 const symbol=frame(r,"Vehicle symbol",{width:44,height:44,justifyContent:"center",alignItems:"center",fill:"#F0ECFC",cornerRadius:12});icon(symbol,"Vehicle icon","car",C.purple,24);
 const labels=frame(r,"Vehicle identity",{gap:3});text(labels,"Plate",plate,14,C.ink,"600");text(labels,"Model",name,12,C.muted);
 const details=frame(r,"Vehicle status",{width:90,gap:3});text(details,"Status",status,11,status==="Offline"?C.red:C.green);text(details,"Energy",energy,12,C.muted);
 separator(p);
};
const map = (p,height=230) => {
 const m=frame(p,"Jakarta map schematic",{height,layout:"none",fill:"#EAEFEC",cornerRadius:16,clip:true});
 for (const [x,y,w,h] of [[0,55,350,10],[0,150,350,8],[80,0,9,height],[235,0,8,height]]) Insert(m,{type:"rectangle",name:"Street grid",x,y,width:w,height:h,fill:"#FFFFFF"});
 Insert(m,{type:"rectangle",name:"Sudirman corridor",x:156,y:0,width:14,height,fill:"#D4D8E6"});
 Insert(m,{type:"text",name:"District label",x:195,y:85,content:"SETIABUDI",fontFamily:"Inter",fontSize:10,letterSpacing:1,fill:C.muted});
 for(const [x,y,color] of [[147,78,C.purple],[238,163,C.green],[69,126,C.red]])Insert(m,{type:"icon",name:"Vehicle location",x,y,width:24,height:24,library:"lucide",icon:"map-pin",fill:color});
 Insert(m,{type:"text",name:"Map data label",x:16,y:height-26,content:"Jakarta · peta skematik demo",fontFamily:"Inter",fontSize:10,fill:C.muted});
 return m;
};
screens=[];
const overview=phone("Ringkasan armada",0,base.x);screens.push(overview.s);
const status=frame(overview.content,"Fleet status",{padding:20,fill:C.ink,cornerRadius:16,gap:18});text(status,"Status heading","Status armada",13,"#C5C5DC");
const metrics=row(status,"Status metrics",{gap:20});
for(const [value,label,color] of [["6","Total unit","#FFFFFF"],["2","Berjalan","#93E1C4"],["1","Offline","#FFBAC0"]]){
 const metric=frame(metrics,label,{gap:6});text(metric,label+" value",value,32,color,"600");text(metric,label+" label",label,12,"#C5C5DC");
}
separator(status);text(status,"Fleet shortcut","Lihat armada →",14,"#FFFFFF","600");
const mapTitle=row(overview.content,"Map heading");text(mapTitle,"Map title","Posisi kendaraan",16,C.ink,"600");text(mapTitle,"Open map","Buka peta ↗",12,C.purple,"600");map(overview.content);
const selected=frame(overview.content,"Selected vehicle",{padding:18,fill:"#FFFFFF",cornerRadius:16});text(selected,"Plate","B 1248 REV",16,C.ink,"700");text(selected,"Model","Hyundai IONIQ 5 · Berjalan",13,C.muted);text(selected,"Readings","42 km/jam              78% baterai",20,C.ink,"600");action(selected,"Detail kendaraan",true);
text(overview.content,"Attention","3 peringatan belum ditinjau →",14,"#966016","600");text(overview.content,"Demo disclosure","Mode demo · posisi dan telemetri merupakan simulasi.",11,C.muted);nav(overview.s,0);Update(overview.s,{placeholder:false});
const fleet=phone("Armada",1,base.x+470);screens.push(fleet.s);
const search=row(fleet.content,"Search vehicles",{padding:14,fill:"#FFFFFF",cornerRadius:12,stroke:C.line,strokeWidth:1});icon(search,"Search","search");text(search,"Search hint","Cari kendaraan, pelat, atau pengemudi",12,C.muted);
const filters=row(fleet.content,"Powertrain filters",{gap:8});for(const label of ["Semua","EV","Bensin","Offline"]){const chip=row(filters,label+" filter",{width:"fit_content",padding:[9,12],cornerRadius:10,fill:label==="Semua"?"#F0ECFC":"#FFFFFF"});const l=text(chip,label,label,12,label==="Semua"?C.purple:C.muted,"600");Update(l,{textGrowth:"auto"});}
text(fleet.content,"Vehicle count","6 kendaraan",13,C.muted);
const list=frame(fleet.content,"Fleet directory",{gap:0});
for(const data of [["B 1248 REV","Hyundai IONIQ 5","Berjalan","78% baterai"],["B 2086 REV","Toyota Avanza","Berjalan","64% BBM"],["B 3019 REV","BYD Atto 3","Berhenti","26% baterai"],["B 4410 REV","Toyota Innova","Parkir","52% BBM"],["B 5502 REV","Wuling Air EV","Mengisi daya","91% baterai"],["B 6618 REV","Mitsubishi Xpander","Offline","—"]])vehicle(list,...data);
nav(fleet.s,1);Update(fleet.s,{placeholder:false});
const detail=phone("Detail kendaraan",1,base.x+940);screens.push(detail.s);
text(detail.content,"Vehicle model","Hyundai IONIQ 5",22,C.ink,"600");text(detail.content,"Vehicle plate","B 1248 REV · Berjalan",14,C.green);
const hero=frame(detail.content,"Vehicle readings",{padding:20,fill:"#FFFFFF",cornerRadius:16});const readings=row(hero,"Energy and speed");for(const [v,l] of [["78%","Baterai"],["42","km/jam"],["312 km","Estimasi jarak"]]){const r=frame(readings,l,{gap:4});text(r,l+" value",v,22,C.ink,"600");text(r,l+" label",l,11,C.muted);}
text(detail.content,"Location","Jl. Jenderal Sudirman, Jakarta",13,C.muted);separator(detail.content);
text(detail.content,"Telemetry title","Telemetri",18,C.ink,"600");text(detail.content,"Metric selector","Kecepatan                 Baterai",14,C.purple,"600");text(detail.content,"Current telemetry","42.0 km/jam",28,C.ink,"600");text(detail.content,"Time","09:41 · data simulasi",12,C.muted);
const chart=row(detail.content,"Speed samples — illustration",{height:150,gap:8,alignItems:"end"});for(const [value,label] of [[22,"09:36"],[34,"09:37"],[28,"09:38"],[46,"09:39"],[39,"09:40"],[42,"09:41"]]){const col=frame(chart,label+" sample",{height:"fill_container",justifyContent:"end",gap:8});Insert(col,{type:"rectangle",name:label+" speed bar",width:"fill_container",height:value*2,fill:C.purple,cornerRadius:[4,4,0,0]});text(col,label+" time",label,9,C.muted);}
text(detail.content,"Chart disclosure","Ilustrasi grafik · implementasi memakai garis dan waktu pengukuran.",11,C.muted);separator(detail.content);text(detail.content,"Driver","Andi Pratama",16,C.ink,"600");text(detail.content,"Driver role","Pengemudi ditugaskan",12,C.muted);action(detail.content,"Atur pengemudi",true);nav(detail.s,1);Update(detail.s,{placeholder:false});
Print({screens,button});
Print(Get(n=>screens.includes(n.id)?{name:n.name,id:n.id}:undefined));
