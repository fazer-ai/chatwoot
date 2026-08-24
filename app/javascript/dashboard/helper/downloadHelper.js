import fromUnixTime from 'date-fns/fromUnixTime';
import format from 'date-fns/format';

export const downloadCsvFile = (fileName, content) => {
  const contentType = 'data:text/csv;charset=utf-8;';
  const blob = new Blob([content], { type: contentType });
  const url = URL.createObjectURL(blob);

  const link = document.createElement('a');
  link.setAttribute('download', fileName);
  link.setAttribute('href', url);
  link.click();
  return link;
};

// Keeps the same report downloaded for two different filters in two files.
const slugifyFilterName = name =>
  name
    .toString()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '');

export const generateFileName = ({
  type,
  to,
  businessHours = false,
  filteredBy = '',
}) => {
  let name = `${type}-report-${format(fromUnixTime(to), 'dd-MM-yyyy')}`;
  const filterSlug = filteredBy ? slugifyFilterName(filteredBy) : '';
  if (filterSlug) {
    name = `${name}-${filterSlug}`;
  }
  if (businessHours) {
    name = `${name}-business-hours`;
  }
  return `${name}.csv`;
};
