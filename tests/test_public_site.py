from html.parser import HTMLParser
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'site'
SOURCE_URL = 'https://github.com/zerodrift/leanetrm'

class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.links, self.assets, self.headings, self.scripts = [], [], [], []
        self.feed(text)
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'a': self.links.append(a.get('href', ''))
        if tag == 'link' and a.get('rel') in ('stylesheet', 'icon'): self.assets.append(a['href'])
        if tag == 'img': self.assets.append(a['src'])
        if tag == 'h1': self.headings.append(tag)
        if tag == 'script': self.scripts.append(a)

class PublicSite(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = (ROOT / 'index.html').read_text()
        cls.page = Page(cls.text)

    def test_open_source_is_visible_and_links_to_the_repository_and_license(self):
        self.assertIn('Open source', self.text)
        self.assertIn(SOURCE_URL, self.page.links)
        self.assertIn(SOURCE_URL + '/blob/master/LICENSE', self.page.links)
        self.assertIn('Apache 2.0', self.text)

    def test_workspace_is_an_explicit_same_domain_link(self):
        self.assertGreaterEqual(self.page.links.count('/app'), 2)
        self.assertTrue(all(not x.startswith('https://app.') for x in self.page.links))

    def test_landing_is_readable_without_javascript_or_accounts(self):
        self.assertEqual(self.page.headings, ['h1'])
        self.assertFalse(self.page.scripts)
        self.assertIn('Synthetic illustration', self.text)
        self.assertIn('href="#main"', self.text)

    def test_all_public_assets_and_fragment_targets_exist(self):
        for url in self.page.assets:
            self.assertTrue(url.startswith('/_landing/'), url)
            self.assertTrue((ROOT / url.removeprefix('/_landing/')).is_file(), url)
        for link in self.page.links:
            if link.startswith('#'):
                self.assertIn(f'id="{link[1:]}"', self.text)

if __name__ == '__main__':
    unittest.main()
