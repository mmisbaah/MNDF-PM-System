type PdfSection={heading:string;lines:string[]};
type PdfLine={text:string;kind:"title"|"subtitle"|"heading"|"body"|"spacer"};
const escapePdf=(value:string)=>value.replaceAll("\\","\\\\").replaceAll("(","\\(").replaceAll(")","\\)").replaceAll(/[^\x20-\x7E]/g,"?");
function wrap(text:string,width=88){const words=text.replaceAll(/\s+/g," ").trim().split(" ");const lines:string[]=[];let line="";for(const word of words){if(`${line} ${word}`.trim().length>width){if(line)lines.push(line);line=word;}else line=`${line} ${word}`.trim();}if(line)lines.push(line);return lines.length?lines:["-"];}
export function buildPrintablePdf(title:string,subtitle:string,sections:PdfSection[]):Buffer{
  const pages:PdfLine[][]=[];let page:PdfLine[]=[];const maxLines=43;
  const startPage=(continued=false)=>{page=[];if(continued)page.push({text:title,kind:"subtitle"},{text:`${subtitle} - continued`,kind:"body"},{text:"",kind:"spacer"});else page.push({text:title,kind:"title"},{text:subtitle,kind:"subtitle"},{text:"",kind:"spacer"});};
  const finishPage=()=>{if(page.length)pages.push(page);};startPage();
  for(const section of sections){const body=section.lines.flatMap(line=>wrap(line).map(text=>({text,kind:"body" as const})));
    if(page.length+Math.min(body.length,2)+2>maxLines){finishPage();startPage(true);}page.push({text:section.heading,kind:"heading"});
    for(const line of body){if(page.length>=maxLines){finishPage();startPage(true);page.push({text:`${section.heading.replace(/:$/,"")} (continued):`,kind:"heading"});}page.push(line);}if(page.length<maxLines)page.push({text:"",kind:"spacer"});}
  finishPage();
  const objects:string[]=[];const add=(value:string)=>{objects.push(value);return objects.length;};const catalog=add("");const pagesId=add("");
  const regularFont=add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>");const boldFont=add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>");const pageIds:number[]=[];
  pages.forEach((lines,pageIndex)=>{let y=790;const commands=["BT"];lines.forEach((line)=>{const bold=line.kind==="title"||line.kind==="heading";const size=line.kind==="title"?18:line.kind==="heading"?13:line.kind==="subtitle"?11:10;commands.push(`/${bold?"F2":"F1"} ${size} Tf`,`1 0 0 1 50 ${y} Tm (${escapePdf(line.text)}) Tj`);y-=line.kind==="title"?28:line.kind==="heading"?22:line.kind==="spacer"?10:16;});
    commands.push(`/F1 8 Tf 1 0 0 1 50 25 Tm (Performance Tracker - member-visible report) Tj`,`/F1 9 Tf 1 0 0 1 500 25 Tm (Page ${pageIndex+1} of ${pages.length}) Tj`,`ET`);const stream=commands.join("\n");const streamId=add(`<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}\nendstream`);pageIds.push(add(`<< /Type /Page /Parent ${pagesId} 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 ${regularFont} 0 R /F2 ${boldFont} 0 R >> >> /Contents ${streamId} 0 R >>`));});
  objects[catalog-1]=`<< /Type /Catalog /Pages ${pagesId} 0 R >>`;objects[pagesId-1]=`<< /Type /Pages /Kids [${pageIds.map(id=>`${id} 0 R`).join(" ")}] /Count ${pageIds.length} >>`;
  let pdf="%PDF-1.4\n";const offsets=[0];objects.forEach((object,index)=>{offsets.push(Buffer.byteLength(pdf));pdf+=`${index+1} 0 obj\n${object}\nendobj\n`;});const xref=Buffer.byteLength(pdf);pdf+=`xref\n0 ${objects.length+1}\n0000000000 65535 f \n${offsets.slice(1).map(offset=>`${String(offset).padStart(10,"0")} 00000 n `).join("\n")}\ntrailer << /Size ${objects.length+1} /Root ${catalog} 0 R >>\nstartxref\n${xref}\n%%EOF`;return Buffer.from(pdf,"ascii");
}
