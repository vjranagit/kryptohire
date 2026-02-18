import { NextRequest, NextResponse } from 'next/server';

export async function GET(req: NextRequest) {
  console.log('[TEST] Test route called');
  return NextResponse.json({ success: true, message: "Test route works" });
}
