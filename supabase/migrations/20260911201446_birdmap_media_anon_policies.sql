-- Lets the app's public anon key upload sighting photo/audio fallback copies
-- directly to Supabase Storage (no backend to proxy through — see
-- ios/BirdMap/BirdMap/Networking/SupabaseStorage.swift and
-- ml_pipeline/publish_model.py, which uses S3-protocol credentials instead
-- and doesn't need these policies). Anyone holding the anon key (i.e. anyone
-- with the app installed) can write to this bucket; there's no per-user
-- ownership check, matching the tradeoff already accepted by the Firestore
-- side of this architecture.
create policy "Allow anon uploads to birdmap-media"
on storage.objects for insert
to anon
with check (bucket_id = 'birdmap-media');

-- SupabaseStorage.uploadFallback sends x-upsert: true so re-uploading the
-- same sighting's path (e.g. a retry) overwrites rather than erroring.
create policy "Allow anon overwrite in birdmap-media"
on storage.objects for update
to anon
using (bucket_id = 'birdmap-media')
with check (bucket_id = 'birdmap-media');
