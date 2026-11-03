import type { Metadata } from 'next';
import './globals.css';
export const metadata:Metadata={title:'Omniscient · Incident Knowledge',description:'Turn incidents into institutional knowledge. RCA documents, evidence search, and accountable follow-through.'};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="en"><body>{children}</body></html>}
