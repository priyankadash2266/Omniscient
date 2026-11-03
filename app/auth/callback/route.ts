import {NextRequest,NextResponse} from 'next/server';
import {createClient} from '../../../lib/supabase-server';
export async function GET(request:NextRequest){const url=new URL(request.url);const code=url.searchParams.get('code');if(code){const client=await createClient();const {error}=await client.auth.exchangeCodeForSession(code);if(!error)return NextResponse.redirect(new URL('/',request.url));}return NextResponse.redirect(new URL('/login?error=confirmation',request.url));}
