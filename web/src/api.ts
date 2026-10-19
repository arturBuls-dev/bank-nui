import { fetchNui, isInGame } from './nui';
import type { Account, HistoryRow, Result } from './types';

// In the game every call goes to the server through client.lua. In a normal browser (development)
// a small fake bank answers instead, so the window can be designed without starting the game.

const DEV_ACCOUNT: Account = {
  bankName: 'City Bank',
  id: 'ABC12345',
  name: 'Jordan Blake',
  cash: 2400,
  bank: 18250,
  limits: { maxAmount: 1000000, maxTransfer: 500000 },
  history: [
    { kind: 'transfer_in', amount: 1200, counterparty: 'Riley Santos', balanceAfter: 18250, at: Math.floor(Date.now() / 1000) - 3600 },
    { kind: 'withdraw', amount: 500, counterparty: null, balanceAfter: 17050, at: Math.floor(Date.now() / 1000) - 86400 },
    { kind: 'deposit', amount: 3000, counterparty: null, balanceAfter: 17550, at: Math.floor(Date.now() / 1000) - 172800 },
    { kind: 'transfer_out', amount: 750, counterparty: 'Nico Brandt', balanceAfter: 14550, at: Math.floor(Date.now() / 1000) - 259200 },
  ],
};

export function devAccount(): Account {
  return structuredClone(DEV_ACCOUNT);
}

function push(row: HistoryRow) {
  DEV_ACCOUNT.history = [row, ...DEV_ACCOUNT.history].slice(0, 15);
}

function mock(name: string, payload: { amount?: number; target?: string }): Result {
  const amount = Math.floor(Number(payload.amount));
  const now = Math.floor(Date.now() / 1000);
  if (!Number.isFinite(amount) || amount < 1) return { ok: false, error: 'Enter a whole amount.' };

  if (name === 'deposit') {
    if (DEV_ACCOUNT.cash < amount) return { ok: false, error: 'You do not have that much cash.' };
    DEV_ACCOUNT.cash -= amount;
    DEV_ACCOUNT.bank += amount;
    push({ kind: 'deposit', amount, counterparty: null, balanceAfter: DEV_ACCOUNT.bank, at: now });
  } else if (name === 'withdraw') {
    if (DEV_ACCOUNT.bank < amount) return { ok: false, error: 'Not enough money in your bank account.' };
    DEV_ACCOUNT.bank -= amount;
    DEV_ACCOUNT.cash += amount;
    push({ kind: 'withdraw', amount, counterparty: null, balanceAfter: DEV_ACCOUNT.bank, at: now });
  } else {
    const target = (payload.target ?? '').trim().toUpperCase();
    if (target === DEV_ACCOUNT.id) return { ok: false, error: 'You cannot send money to yourself.' };
    if (target.length < 3) return { ok: false, error: 'Account not found.' };
    if (DEV_ACCOUNT.bank < amount) return { ok: false, error: 'Not enough money in your bank account.' };
    DEV_ACCOUNT.bank -= amount;
    push({ kind: 'transfer_out', amount, counterparty: `Account ${target}`, balanceAfter: DEV_ACCOUNT.bank, at: now });
  }

  return { ok: true, data: structuredClone(DEV_ACCOUNT) };
}

export async function callApi(name: 'deposit' | 'withdraw' | 'transfer', payload: { amount: number; target?: string }): Promise<Result> {
  if (!isInGame()) return mock(name, payload);

  const result = await fetchNui<Result>(name, payload);
  return result ?? { ok: false, error: 'No answer from the server.' };
}
