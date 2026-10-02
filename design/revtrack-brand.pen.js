const p = FindEmptySpace({width:1800,height:1350,direction:"bottom",padding:160});
brand = Insert(document,{type:"frame",name:"RevTrack — Brand and components",x:p.x,y:p.y,width:1800,height:600,layout:"horizontal",padding:64,gap:64,fill:"#FFFFFF",placeholder:true});
logo = Insert(brand,{type:"frame",name:"RevTrack route monogram",width:240,height:240,layout:"none",placeholder:true});
Generate("svg",logo,"Create one premium vector logo mark for RevTrack, a fleet operations app. A bold geometric capital R with a sweeping route forming a negative-space forward arrow within the letter. Exactly one cohesive compact silhouette, no text, no surrounding badge, no background, no shadows. Reference direction: top ribbon sweeps horizontally right then curves into the bowl of the R; diagonal lower legs feel like a road and forward movement. Use solid navy #141735 and solid violet #5938D6, white/transparent negative space. Flat precise vector geometry with minimal path count, legible at 24px. Balanced elegant proportions and purposeful route symbolism, no stock generic pin or car icon.");
const copy = Insert(brand,{type:"frame",name:"Brand typography and intent",layout:"vertical",width:700,gap:24});
Insert(copy,{type:"text",name:"RevTrack wordmark",content:"RevTrack",fontFamily:"Inter",fontSize:72,fontWeight:"700",letterSpacing:-3,fill:"#141735"});
Insert(copy,{type:"text",name:"Brand descriptor",content:"FLEET INTELLIGENCE",fontFamily:"Inter",fontSize:14,letterSpacing:3,fill:"#686D82"});
Insert(copy,{type:"text",name:"Product principles",content:"Posisi jelas. Status terbaca. Tindakan tepat.\n\nFokus pada pekerjaan harian: cari kendaraan, periksa telemetri, tinjau peringatan, dan atur operasional. Animasi menunjukkan proses dan hasilnya.",textGrowth:"fixed-width",width:"fill_container",fontFamily:"Inter",fontSize:18,lineHeight:1.6,fill:"#686D82"});
const tokens = Insert(brand,{type:"frame",name:"Color and interaction tokens",width:350,layout:"vertical",gap:18});
for (const [name,color] of [["Navy · #141735","#141735"],["Violet · #5938D6","#5938D6"],["Moving · #18765C","#18765C"],["Attention · #966016","#966016"],["Offline · #B43C48","#B43C48"]]) {
  const row = Insert(tokens,{type:"frame",name:name,layout:"horizontal",width:"fill_container",gap:16,alignItems:"center"});
  Insert(row,{type:"rectangle",name:name+" swatch",width:32,height:32,cornerRadius:8,fill:color});
  Insert(row,{type:"text",name:name+" label",content:name,fontFamily:"Inter",fontSize:14,fill:"#141735"});
}
Print({brand,logo,x:p.x,y:p.y});
Print(Get(brand,(n,c)=>c.problems?{name:n.name,problem:c.problems}:undefined));
