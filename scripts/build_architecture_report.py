#!/usr/bin/env python3
"""Render the requested research PDF; run with .local/report-env/bin/python.

Direct PDF edition. The original System Design reference.docx is never modified.
The report follows its architecture/contract/security/operations decision structure.
"""
from pathlib import Path
import importlib.util
import re
import json
from xml.sax.saxutils import escape
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT
from reportlab.platypus import (
    BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, Table,
    TableStyle, PageBreak, Flowable, KeepTogether,
)

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('content', ROOT/'docs/research/report_content.py')
content = importlib.util.module_from_spec(spec)
spec.loader.exec_module(content)
OUT = ROOT/'artifacts/reports/RevTrack-System-Design-2026-10-03.pdf'
QA = ROOT/'.local/report-qa'
QA.mkdir(parents=True, exist_ok=True)
for name, file in [('Arial','Arial.ttf'),('Arial-Bold','Arial Bold.ttf'),('Arial-Italic','Arial Italic.ttf')]:
    pdfmetrics.registerFont(TTFont(name, '/System/Library/Fonts/Supplemental/'+file))
pdfmetrics.registerFontFamily('Arial',normal='Arial',bold='Arial-Bold',italic='Arial-Italic',boldItalic='Arial-Bold')
INK=colors.HexColor('#092b4c')
BLUE=colors.HexColor('#426783')
TEXT=colors.HexColor('#263649')
PALE=colors.HexColor('#eef4f8')
LINE=colors.HexColor('#d3e1eb')
W,H=612,792
M=50.4
CW=W-2*M
styles={
 'body':ParagraphStyle('body',fontName='Arial',fontSize=10.2,leading=14.5,textColor=TEXT,spaceAfter=8),
 'h':ParagraphStyle('h',fontName='Arial-Bold',fontSize=12,leading=16,textColor=INK,spaceBefore=6,spaceAfter=6,keepWithNext=True),
 'title':ParagraphStyle('title',fontName='Arial-Bold',fontSize=24,leading=29,textColor=INK,spaceAfter=13,keepWithNext=True),
 'tag':ParagraphStyle('tag',fontName='Arial-Bold',fontSize=8.4,leading=11,textColor=BLUE,spaceAfter=7,keepWithNext=True),
 'lead':ParagraphStyle('lead',fontName='Arial-Bold',fontSize=13,leading=18,textColor=INK,spaceAfter=13),
 'small':ParagraphStyle('small',fontName='Arial',fontSize=8.5,leading=11.5,textColor=BLUE,spaceAfter=5),
 'cell':ParagraphStyle('cell',fontName='Arial',fontSize=9.1,leading=12.4,textColor=TEXT),
 'th':ParagraphStyle('th',fontName='Arial-Bold',fontSize=9.1,leading=12.4,textColor=INK),
 'code':ParagraphStyle('code',fontName='Courier',fontSize=8.4,leading=12,textColor=INK,spaceAfter=8),
 'bullet':ParagraphStyle('bullet',fontName='Arial',fontSize=10.1,leading=14,textColor=TEXT,leftIndent=12,firstLineIndent=-10,spaceAfter=5),
}

def markup(text):
    text=escape(text)
    text=re.sub(r'\[S(\d+)\]',lambda m: '<link href="'+content.SOURCES[int(m[1])-1][1]+'" color="#426783">[S'+m[1]+']</link>',text)
    return text

def p(text,style='body'):
    return Paragraph(markup(text), styles[style])

def table(headers, rows):
    n=len(headers)
    widths=([.23,.40,.37] if n==3 else [.16,.18,.23,.21,.22])
    data=[[p(x,'th') for x in headers]]+[[p(x,'cell') for x in row] for row in rows]
    t=Table(data,colWidths=[CW*x for x in widths],repeatRows=1,hAlign='LEFT')
    t.setStyle(TableStyle([
       ('BACKGROUND',(0,0),(-1,0),colors.HexColor('#d0e2f0')),
       ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.HexColor('#f4f7fa'),colors.white]),
       ('VALIGN',(0,0),(-1,-1),'TOP'),
       ('LEFTPADDING',(0,0),(-1,-1),8),('RIGHTPADDING',(0,0),(-1,-1),8),
       ('TOPPADDING',(0,0),(-1,-1),7),('BOTTOMPADDING',(0,0),(-1,-1),7),
       ('LINEBELOW',(0,0),(-1,0),.65,colors.white),
       ('LINEBELOW',(0,1),(-1,-1),.35,LINE),
    ]))
    return [t,Spacer(1,10)]

class Diagram(Flowable):
    def __init__(self,kind):
        Flowable.__init__(self)
        self.kind=kind; self.width=CW; self.height=181 if kind=='architecture' else 146
    def draw(self):
        c=self.canv
        def box(x,y,w,h,title,sub,dark=False):
            c.setFillColor(INK if dark else PALE); c.setStrokeColor(LINE)
            c.roundRect(x,y,w,h,7,fill=1,stroke=0)
            c.setFillColor(colors.white if dark else INK)
            c.setFont('Arial-Bold',9.5);c.drawCentredString(x+w/2,y+h-18,title)
            c.setFont('Arial',8);c.drawCentredString(x+w/2,y+11,sub)
        def arrow(x1,y1,x2,y2):
            c.setStrokeColor(BLUE);c.setFillColor(BLUE);c.setLineWidth(1)
            c.line(x1,y1,x2,y2)
            import math
            angle=math.atan2(y2-y1,x2-x1)
            path=c.beginPath();path.moveTo(x2,y2)
            path.lineTo(x2-5*math.cos(angle-.5),y2-5*math.sin(angle-.5))
            path.lineTo(x2-5*math.cos(angle+.5),y2-5*math.sin(angle+.5));path.close()
            c.drawPath(path,fill=1,stroke=0)
        bw=154; xs=[0,178,357]; hh=49
        if self.kind=='architecture':
            for x,title,sub in zip(xs,['Perangkat / gateway','MQTT / ingestion Go','PostgreSQL + outbox'],['Sample + buffer lokal','Identity, validasi, dedup','Fakta, latest state, jobs']):
                box(x,118,bw,hh,title,sub,x==178)
            arrow(154,142,178,142);arrow(332,142,357,142)
            box(357,35,bw,hh,'Worker / agent','Analisis asinkron')
            box(178,35,bw,hh,'Live gateway','Subscription terotorisasi',True)
            box(0,35,bw,hh,'Flutter','Snapshot + delta + freshness')
            arrow(433,118,433,84);arrow(381,118,282,84);arrow(178,59,154,59)
            c.setFillColor(BLUE);c.setFont('Arial',8)
            c.drawString(0,13,'Stream durable dapat ditambahkan sebelum projector saat kebutuhan meningkat.')
        else:
            for x,title,sub in zip(xs,['Market connector','Normalisasi + state','Strategi / agent'],['Sequence, snapshot, gap','Timestamp + evidence','Sinyal / proposal']):
                box(x,89,bw,hh,title,sub,x==178)
            arrow(154,113,178,113);arrow(332,113,357,113)
            for x,title,sub in zip(xs,['Broker / exchange','Executor + ledger','Risk engine'],['Acknowledgement / fill','Idempotency + reconcile','Aturan + batas + kill switch']):
                box(x,10,bw,hh,title,sub,x==357)
            arrow(433,89,433,59);arrow(357,34,332,34);arrow(178,34,154,34)

class Report(BaseDocTemplate):
    def __init__(self,path):
        super().__init__(str(path),pagesize=(W,H),leftMargin=M,rightMargin=M,topMargin=55,bottomMargin=46,
            title='RevTrack: Sistem Realtime, IoT dan Agentic AI',author='RevTrack — kajian teknis',
            subject='Architecture decision report; proposed targets, capacity, security, operations and cost')
        self.starts=[]
        self.addPageTemplates(PageTemplate('normal',frames=[Frame(M,46,CW,H-101,id='body',leftPadding=0,rightPadding=0,topPadding=0,bottomPadding=0)],onPage=self.furniture))
    def furniture(self,c,doc):
        if doc.page>1:
            c.saveState();c.setFont('Arial',8);c.setFillColor(BLUE)
            c.drawString(M,H-31,'REVTRACK  /  SYSTEM DESIGN & TECHNOLOGY REVIEW')
            c.setStrokeColor(LINE);c.line(M,H-39,W-M,H-39)
            c.setFont('Arial',8);c.drawString(M,25,'Usulan teknis  •  3 Oktober 2026  •  v1.0')
            c.drawRightString(W-M,25,str(doc.page));c.restoreState()
    def afterFlowable(self,flowable):
        if getattr(flowable,'section_key',None):
            self.canv.bookmarkPage(flowable.section_key)
            self.canv.addOutlineEntry(flowable.getPlainText(),flowable.section_key,0)
            self.starts.append((flowable.section_key,self.page,flowable.getPlainText()))

def heading(text,key):
    a=p(text,'title');a.section_key=key;return a

def build(toc=None):
    story=[]
    story += [Spacer(1,114),p('REVTRACK','tag'),p('Sistem realtime, IoT dan agentic AI','title'),
      p('Fondasi yang matang untuk 1.000+ kendaraan<br/>dan pengembangan pipeline pasar'.replace('<br/>',' '),'lead'),Spacer(1,49),
      p('SYSTEM DESIGN / TECHNOLOGY REVIEW','tag'),
      p('Kajian end-to-end: pilihan stack, kapasitas, latency, data, hosting, keamanan, agent, biaya dan rencana implementasi.'),Spacer(1,37)]
    story += table(['STATUS','OWNER / PEMBACA','DIPERBARUI'],[['Usulan untuk kajian','Founder dan tim RevTrack','3 Oktober 2026']])
    story += [p('Dasar kajian','h'),p('Dokumentasi primer vendor dan proyek; pemeriksaan terbatas repo RevTrack; perhitungan kapasitas dengan asumsi eksplisit. Bukan hasil load test atau janji SLA.'),
       p('Cara membaca','h'),p('Mulai dari keputusan dan target, lalu ikuti aliran data sampai operasi. Referensi [Sxx] dapat diklik. Bookmark PDF membantu berpindah bab.'),PageBreak()]
    story += [p('PETA BACA','tag'),heading('Isi laporan','contents')]
    mapping={k:n for k,n,_ in (toc or [])}
    for i,s in enumerate(content.PAGES):
        label=f'{i+1:02d}   {s["title"]}'
        pg=str(mapping.get(f'section-{i}',i+3))
        story += [Table([[Paragraph(f'<link href="#section-{i}" color="#092b4c">{escape(label)}</link>',styles['body']),p(pg,'small')]],colWidths=[CW-35,35],style=TableStyle([('LEFTPADDING',(0,0),(-1,-1),0),('RIGHTPADDING',(0,0),(-1,-1),0),('BOTTOMPADDING',(0,0),(-1,-1),0),('TOPPADDING',(0,0),(-1,-1),0)]))]
    story += [Spacer(1,8),p('Referensi primer dan catatan metodologi berada di bagian akhir. Harga, lisensi, versi serta ketersediaan perlu diverifikasi lagi saat keputusan pembelian.'),PageBreak()]
    for i,section in enumerate(content.PAGES):
        tag=f'{i+1:02d} / '+section['tag'].split(' / ',1)[1]
        story += [p(tag,'tag'),heading(section['title'],f'section-{i}')]
        for kind,value in section['blocks']:
            if kind in ('p','h','lead'):
                story.append(p(value, 'body' if kind=='p' else kind))
            elif kind=='bullets':
                for text in value: story.append(p('• '+text,'bullet'))
            elif kind=='table': story.extend(table(*value))
            elif kind=='callout':
                t=Table([[p(value,'cell')]],colWidths=[CW])
                t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,-1),PALE),('BOX',(0,0),(-1,-1),.5,LINE),('LEFTPADDING',(0,0),(-1,-1),11),('RIGHTPADDING',(0,0),(-1,-1),11),('TOPPADDING',(0,0),(-1,-1),10),('BOTTOMPADDING',(0,0),(-1,-1),10)]))
                story.extend([t,Spacer(1,10)])
            elif kind=='code':
                story.append(Paragraph(escape(value).replace('\n','<br/>'),styles['code']))
            elif kind=='diagram': story.extend([Diagram(value),Spacer(1,7)])
            elif kind=='refs':
                links='  ·  '.join(f'<link href="{content.SOURCES[n-1][1]}">S{n:02d}</link>' for n in value)
                story.append(Paragraph('Rujukan: '+links,styles['small']))
        story.append(PageBreak())
    # Named references with clickable URLs, readable without a separate web session.
    for offset in range(0,len(content.SOURCES),12):
        story.extend([p('SUMBER PRIMER / DIAKSES 3 OKTOBER 2026','tag'),heading('Referensi '+str(offset//12+1),'refs-'+str(offset))])
        if offset==0:
            story.append(p('Sumber mendukung kemampuan produk dan fakta harga. Rancangan, target SLO, asumsi sizing dan roadmap merupakan analisis untuk RevTrack. Tidak ada klaim bahwa vendor menjamin hasil benchmark dalam laporan ini.','small'))
        for n,(title,url) in enumerate(content.SOURCES[offset:offset+12],offset+1):
            label=Paragraph(f'<b>[S{n:02d}] {escape(title)}</b>',styles['body'])
            link=Paragraph('<link href="'+url+'" color="#426783">'+escape(url)+'</link>',styles['small'])
            story.append(KeepTogether([label,link,Spacer(1,7)]))
        if offset+12<len(content.SOURCES): story.append(PageBreak())
    doc=Report(OUT);doc.build(story)
    return doc.starts

if __name__=='__main__':
    starts=build();starts=build(starts)
    (QA/'sections.json').write_text(json.dumps(starts,indent=2))
    import pymupdf
    pdf=pymupdf.open(OUT)
    text='\n'.join(page.get_text() for page in pdf)
    (QA/'extracted.txt').write_text(text)
    issues=[]
    for i,page in enumerate(pdf):
        if len(page.get_text().strip())<80:issues.append(f'page {i+1}: nearly empty')
        for b in page.get_text('blocks'):
            if b[0]<15 or b[2]>W-15 or b[1]<8 or b[3]>H-10:issues.append(f'page {i+1}: bounds {b[:4]}')
        page.get_pixmap(matrix=pymupdf.Matrix(1.2,1.2)).save(str(QA/f'page-{i+1:02d}.png'))
    print(json.dumps({'pdf':str(OUT),'pages':len(pdf),'bytes':OUT.stat().st_size,'sections':starts,'layout_warnings':issues},indent=2))
