-- 1. Avatars bucket: restrict reads to the owner's own folder
DROP POLICY IF EXISTS "Avatars: authenticated read" ON storage.objects;
CREATE POLICY "Avatars: owner read"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- 2. lookup_referrer: no longer executable by anonymous visitors.
--    The signup referrer preview now runs server-side with elevated privileges.
REVOKE EXECUTE ON FUNCTION public.lookup_referrer(text) FROM PUBLIC, anon;