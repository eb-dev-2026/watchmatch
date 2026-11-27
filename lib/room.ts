import { supabase } from "./supabase";
import type { DiscoveryMode, MediaType } from "./tmdb";

export function generateRoomCode(): string {
  return String(Math.floor(1000 + Math.random() * 9000));
}

export function getOrCreateGuestId(): string {
  if (typeof window === "undefined") return "server";
  let id = localStorage.getItem("watchmatch_guest_id");
  if (!id) {
    id = crypto.randomUUID();
    localStorage.setItem("watchmatch_guest_id", id);
  }
  return id;
}

export interface CreateRoomParams {
  mediaType: MediaType;
  discoveryMode: DiscoveryMode;
  minScore: number;
}

export async function createRoom(params: CreateRoomParams) {
  const hostId = getOrCreateGuestId();
  const code = generateRoomCode();
  const { data, error } = await supabase
    .from("rooms")
    .insert({
      code,
      host_id: hostId,
      media_type: params.mediaType,
      discovery_mode: params.discoveryMode,
      min_score: params.minScore,
      status: "waiting",
    })
    .select()
    .single();

  if (error) throw error;
  return { room: data, hostId };
}

export async function joinRoom(code: string) {
  const guestId = getOrCreateGuestId();
  const { data: room, error } = await supabase.rpc("join_room", {
    p_code: code,
    p_user_id: guestId
  })

  if (error) throw new Error(error?.message);

  return { room, guestId };
}

export async function recordSwipe(params: {
  roomId: string;
  userId: string;
  mediaId: number;
  mediaType: MediaType;
  direction: "like" | "pass";
}) {
  const { data, error } = await supabase.rpc("swipe_and_match", {
    p_room_id: params.roomId,
    p_user_id: params.userId,
    p_media_id: params.mediaId,
    p_media_type: params.mediaType,
    p_direction: params.direction,
  });
  if (error) throw error;
  return data === true;
}

export function subscribeToRoom(
  roomId: string,
  onSwipe: (payload: any) => void,
  onMatch: (payload: any) => void
) {
  const channel = supabase
    .channel(`room-${roomId}`)
    .on(
      "postgres_changes",
      { event: "INSERT", schema: "public", table: "swipes", filter: `room_id=eq.${roomId}` },
      onSwipe
    )
    .on(
      "postgres_changes",
      { event: "INSERT", schema: "public", table: "matches", filter: `room_id=eq.${roomId}` },
      onMatch
    )
    .subscribe();

  return () => {
    supabase.removeChannel(channel);
  };
}
