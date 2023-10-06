import { LocatorText } from "@d-i-t-a/reader/dist/types/model/Locator";

/**
 * An interface representing the Readium Locator object.
 */
export interface Locator {
  href: string;
  type: string;
  target?: number;
  title?: string;
  text: LocatorText;
  locations?: {
    progression: number;
    position?: number;
    totalProgression?: number;
  };
}
