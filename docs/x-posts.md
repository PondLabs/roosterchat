# X posts in the chat

A status link previews as an X card, laid out like iframely's: the author's avatar, name, verified mark and @handle, the X logo, the post's text, its media, the quoted post, and the date with reply, repost and like counts. The links are `x.com`, `twitter.com` and `mobile.` hosts, and the fxtwitter, vxtwitter, fixupx, fixvx and twittpr mirrors, in the `/<user>/status/<id>` form. Clicking the card opens the post. Links, @mentions and #hashtags in the text open on their own, and so does the quoted post.

`TwitterProvider` (`rooster/lib/client/components/video_embed/providers/twitter_provider.dart`) recognises the link and fetches the status. `XPost` (`.../video_embed/x_post.dart`) is the parsed status. `MatrixUrlPreviewComponent._xPostPreview` puts it on `UrlPreviewData.xPost`, and `UrlPreviewWidget._buildXCard` draws it.

## Data: fxtwitter's API

`https://api.fxtwitter.com/<user>/status/<id>` returns the status as JSON without a key. Its `tweet` object has `author` (`name`, `screen_name`, `avatar_url`, `verification`), `text` (t.co links expanded, the trailing media link dropped), `media.all` (photos, videos, GIFs with size and thumbnail), `quote` (a nested status of the same shape), `created_timestamp`, `replies`, `retweets` and `likes`.

The reply's `content-type` is `application/json` with no charset, and package:http would read that as Latin-1. The body is therefore decoded as UTF-8 by hand, so emoji and curly quotes survive.

It sends `access-control-allow-origin: *`, so native and web builds make the same request. `pbs.twimg.com` images and `video.twimg.com` MP4s echo the page's origin back, so they load on web too.

X's own `cdn.syndication.twimg.com/tweet-result` was not used. It only allows `https://platform.twitter.com` as an origin, and it needs a token computed from the id.

The status JSON is cached per status id in the provider, so the card, its video and its photos come from one request. A failed fetch is not cached. The preview component also caches the finished preview per URL.

## Media

- **Photos:** one photo keeps its shape. Two to four photos show in X's grid. Tapping a photo opens the lightbox with every photo.
- **Video or GIF:** the thumbnail with a play button. Play opens the MP4 in the video dialog, the same player as an X video link had before.
- **Quoted post:** a smaller nested card with its first photo or video thumbnail.

## Fallback

If the fetch fails (fxtwitter down, a private or deleted post), the link goes through the usual path: the homeserver's URL preview, then the provider's plain video or photo preview. In an end-to-end encrypted room with URL previews turned off, X links are still read from fxtwitter, as they were before the card. The homeserver is never asked.

## Limitations

- A post with both photos and a video shows only the photos.
- The card shows no polls, community notes, reply context or link cards.
- fxtwitter is a third-party service. When it stops answering, posts fall back to the plain preview.

Check a status by hand:

```sh
curl -s -H 'Origin: https://example.com' -D - -o /dev/null \
  https://api.fxtwitter.com/SpaceX/status/1732824684683784516 | grep -i access-control
```

The test fixture `rooster/unit_test/fixtures/x_status_fxtwitter.json` is SpaceX's video post with Ellen's Oscars selfie set as its quote. Both are trimmed from real replies.
