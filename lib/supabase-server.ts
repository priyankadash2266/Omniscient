import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
export async function createClient(){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL, key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
 if(!url||!key)throw new Error('Database configuration is missing.');
 const store=await cookies();
 return createServerClient(url,key,{cookies:{getAll(){return store.getAll()},setAll(values){for(const {name,value,options} of values)store.set(name,value,options)}}});
}
export async function identity(){const supabase=await createClient();const {data:{user},error}=await supabase.auth.getUser();if(error||!user)throw new Error('AUTH');return {supabase,user};}
