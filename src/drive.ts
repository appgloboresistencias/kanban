// Apenas referência externa: não consulta, compartilha ou altera arquivos no Drive.
export function driveFileId(value:string):string|null {
  try {const u=new URL(value);if(u.protocol!=='https:'||u.hostname!=='drive.google.com'||u.username||u.password||u.port)return null;
    const match=u.pathname.match(/^\/file\/d\/([A-Za-z0-9_-]{10,200})(?:\/(?:view|preview))?\/?$/);
    const id=match?.[1]||(u.pathname==='/open'&&u.search.startsWith('?id=')?u.searchParams.get('id'):null);
    return id&&/^[A-Za-z0-9_-]{10,200}$/.test(id)?id:null;
  }catch{return null;}
}
