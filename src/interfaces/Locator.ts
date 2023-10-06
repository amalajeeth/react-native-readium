/**
 * An interface representing the Readium Locator object.
 */
export interface Locator {
  href: string;
  type: string;
  target?: number;
  title?: string;
  text: Text;
  locations?: {
    progression: number;
    position?: number;
    totalProgression?: number;
  };
}
