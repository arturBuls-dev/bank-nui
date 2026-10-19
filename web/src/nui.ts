import { useEffect } from 'react';

// Game function that returns the resource name. A regular browser does not have it (development mode)
declare function GetParentResourceName(): string;

export const isInGame = (): boolean => typeof GetParentResourceName === 'function';

// Send data to Lua: RegisterNUICallback('<eventName>')
export async function fetchNui<T = unknown>(eventName: string, data: unknown = {}): Promise<T | undefined> {
  if (!isInGame()) {
    console.log('[dev] fetchNui', eventName, data);
    return undefined;
  }
  const resp = await fetch(`https://${GetParentResourceName()}/${eventName}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  });
  return resp.json();
}

// Receive messages from Lua: SendNUIMessage({ action = '...', ... })
export function useNuiEvent<T = unknown>(action: string, handler: (data: T) => void) {
  useEffect(() => {
    const listener = (event: MessageEvent) => {
      if (event.data?.action === action) handler(event.data as T);
    };
    window.addEventListener('message', listener);
    return () => window.removeEventListener('message', listener);
  }, [action, handler]);
}
