import React, { useEffect, useState, useRef } from 'react';
import { StyleSheet, View, Text, Platform } from 'react-native';
import {
  ReadiumView,
  Settings,
} from 'react-native-readium';
import type { Link, Locator, File, Highlight } from 'react-native-readium';

import RNFS from '../utils/RNFS';
import {
  EPUB_URL,
  EPUB_PATH,
  INITIAL_LOCATION,
  DEFAULT_SETTINGS,
} from '../consts';
import { ReaderButton } from './ReaderButton';
import { TableOfContents } from './TableOfContents';
import { Settings as ReaderSettings } from './Settings';

export const Reader: React.FC = () => {
  const [toc, setToc] = useState<Link[] | null>([]);
  const [file, setFile] = useState<File>();
  const [location, setLocation] = useState<Locator | Link>();
  const [settings, setSettings] = useState<Partial<Settings>>(DEFAULT_SETTINGS);
  const ref = useRef<any>();

  useEffect(() => {
    async function run() {

      if (Platform.OS === 'web') {
        setFile({
          url: EPUB_URL,
          highlights: [],
          initialLocation: INITIAL_LOCATION,
        });
      } else {
        const exists = await RNFS.exists(EPUB_PATH);
        if (!exists) {
          console.log(`Downloading file: '${EPUB_URL}'`);
          const { promise } = RNFS.downloadFile({
            fromUrl: EPUB_URL,
            toFile: EPUB_PATH,
            background: true,
            discretionary: true,
          });

          // wait for the download to complete
          await promise;
        } else {
          console.log(`File already exists. Skipping download.`);
        }

        setFile({
          url: EPUB_PATH,
          highlights: [
            {
              bookId: 'urn:uuid:8a5c1522-197b-11e7-8b0a-4c72b9252ec6',
              locator: {
                href: '/OPS/main3.xml',
                title: 'Chapter 2 - The Carpet-Bag',
                type: 'application/xhtml+xml',
                locations: {
                  position: 24,
                  progression: 0,
                  totalProgression: 0.03392330383480826,
                },
                text: {
                  highlight:
                    'young candidates for the pains and penalties of whaling stop at this same New Bedford, thence to embark on their voyage, it may as well be related that I, for one, had',
                  before:
                    'in December. Much was I disappointed upon learning\nthat the little packet for Nantucket had already sailed, and that\nno way of reaching that place would offer, till the following\nMonday.\nAs most ',
                  after:
                    ' no idea of so doing.\nFor my mind was made up to sail in no other than a Nantucket craft,\nbecause there was a fine, boisterous something about everything\nconnected with that famous old island, which',
                },
              },
              id: '75EA5251-AE61-47A1-9345-A58BB6F3BBF1',
              color: 4,
            },
          ],
          initialLocation: INITIAL_LOCATION,
        });
      }
    }

    run();
  }, []);

  if (file) {
    return (
      <View style={styles.container}>
        <View style={styles.controls}>
          <View style={styles.button}>
            <TableOfContents
              items={toc}
              onPress={(loc) => setLocation({ href: loc.href, type: 'application/xhtml+xml', title: loc.title })}
            />
          </View>
          <View style={styles.button}>
            <ReaderSettings
              settings={settings}
              onSettingsChanged={(s) => setSettings(s)}
            />
          </View>
        </View>

        <View style={styles.reader}>
          {Platform.OS === 'web' ? (
            <ReaderButton
              name="chevron-left"
              style={{ width: '10%' }}
              onPress={() => ref.current?.prevPage()}
            />
          ) : null}
          <View style={styles.readiumContainer}>
            <ReadiumView
              ref={ref}
              file={file}
              location={location}
              settings={settings}
              onLocationChange={(locator: Locator) => setLocation(locator)}
              onTableOfContents={(toc: Link[] | null) => {
                if (toc) setToc(toc);
              }}
              onNewHighlightCreation={(highlight: Highlight) => {
                console.log(highlight);
              }}
            />
          </View>
          {Platform.OS === 'web' ? (
            <ReaderButton
              name="chevron-right"
              style={{ width: '10%' }}
              onPress={() => ref.current?.nextPage()}
            />
          ) : null}
        </View>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Text>downloading file</Text>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    height: Platform.OS === 'web' ? '100vh' : '100%',
  },
  reader: {
    flexDirection: 'row',
    width: '100%',
    height: '90%',
  },
  readiumContainer: {
    width: Platform.OS === 'web' ? '80%' : '100%',
    height: '100%',
  },
  controls: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-end',
  },
  button: {
    margin: 10,
  },
});
